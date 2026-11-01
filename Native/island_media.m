// island_media.c
// MediaRemote 适配层。
//
// macOS 15.4 起 mediaremoted 只对 bundle id 以 com.apple. 开头的进程开放 NowPlaying，
// 第三方 app 直接调用一律拿到空数据。宿主进程用 /usr/bin/perl（bundle id = com.apple.perl）
// 加载本库，调用就发生在有权限的进程里。
//
// 导出符号：
//   mr_run()     取一次快照，打印一行 JSON
//   mr_stream()  长驻，元数据变化时打印一行 JSON
//   mr_command() 从环境变量 MR_COMMAND 读取命令号并下发

#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#pragma mark - MediaRemote 动态符号

typedef void (*FnGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*FnGetPID)(dispatch_queue_t, void (^)(int));
typedef void (*FnGetPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*FnSendCommand)(int, CFDictionaryRef);
typedef void (*FnRegister)(dispatch_queue_t);

static FnGetInfo gGetInfo;
static FnGetPID gGetPID;
static FnGetPlaying gGetPlaying;
static FnSendCommand gSendCommand;
static FnRegister gRegister;

static CFStringRef *gKeyTitle;
static CFStringRef *gKeyArtist;
static CFStringRef *gKeyAlbum;
static CFStringRef *gKeyDuration;
static CFStringRef *gKeyElapsed;
static CFStringRef *gKeyRate;
static CFStringRef *gKeyArtwork;
static CFStringRef *gKeyNotifPlaying;
static CFStringRef *gKeyNotifInfo;

static int loadMediaRemote(void) {
    if (gGetInfo) return 1;
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) return 0;
    gGetInfo = (FnGetInfo)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    gGetPID = (FnGetPID)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID");
    gGetPlaying = (FnGetPlaying)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    gSendCommand = (FnSendCommand)dlsym(h, "MRMediaRemoteSendCommand");
    gRegister = (FnRegister)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    gKeyTitle = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoTitle");
    gKeyArtist = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoArtist");
    gKeyAlbum = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoAlbum");
    gKeyDuration = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoDuration");
    gKeyElapsed = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoElapsedTime");
    gKeyRate = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
    gKeyArtwork = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoArtworkData");
    gKeyNotifPlaying = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    gKeyNotifInfo = (CFStringRef *)dlsym(h, "kMRMediaRemoteNowPlayingInfoDidChangeNotification");
    return gGetInfo && gSendCommand;
}

#pragma mark - JSON 工具

static void putEscaped(FILE *out, CFStringRef s) {
    if (!s) { fputs("\"\"", out); return; }
    CFIndex n = CFStringGetLength(s);
    CFIndex cap = CFStringGetMaximumSizeForEncoding(n, kCFStringEncodingUTF8) + 1;
    char *buf = malloc(cap);
    if (!buf) { fputs("\"\"", out); return; }
    if (!CFStringGetCString(s, buf, cap, kCFStringEncodingUTF8)) { free(buf); fputs("\"\"", out); return; }
    fputc('"', out);
    for (char *p = buf; *p; p++) {
        unsigned char c = (unsigned char)*p;
        switch (c) {
            case '"': fputs("\\\"", out); break;
            case '\\': fputs("\\\\", out); break;
            case '\n': fputs("\\n", out); break;
            case '\r': fputs("\\r", out); break;
            case '\t': fputs("\\t", out); break;
            default:
                if (c < 0x20) fprintf(out, "\\u%04x", c);
                else fputc(c, out);
        }
    }
    fputc('"', out);
    free(buf);
}

static double numFrom(CFDictionaryRef d, CFStringRef *key) {
    if (!d || !key || !*key) return 0;
    CFTypeRef v = CFDictionaryGetValue(d, *key);
    if (!v || CFGetTypeID(v) != CFNumberGetTypeID()) return 0;
    double out = 0;
    CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &out);
    return out;
}

static CFStringRef strFrom(CFDictionaryRef d, CFStringRef *key) {
    if (!d || !key || !*key) return NULL;
    CFTypeRef v = CFDictionaryGetValue(d, *key);
    if (!v || CFGetTypeID(v) != CFStringGetTypeID()) return NULL;
    return (CFStringRef)v;
}

// 封面写到临时文件，返回路径；无封面返回空
static CFStringRef writeArtwork(CFDictionaryRef info) {
    if (!info || !gKeyArtwork || !*gKeyArtwork) return NULL;
    CFTypeRef v = CFDictionaryGetValue(info, *gKeyArtwork);
    if (!v || CFGetTypeID(v) != CFDataGetTypeID()) return NULL;
    CFDataRef data = (CFDataRef)v;
    CFIndex len = CFDataGetLength(data);
    if (len < 16 || len > 8 * 1024 * 1024) return NULL;
    const UInt8 *bytes = CFDataGetBytePtr(data);
    const char *ext = "jpg";
    if (len > 8 && bytes[0] == 0x89 && bytes[1] == 'P') ext = "png";
    char path[512];
    snprintf(path, sizeof(path), "/tmp/flyisland-artwork.%s", ext);
    FILE *f = fopen(path, "wb");
    if (!f) return NULL;
    fwrite(bytes, 1, (size_t)len, f);
    fclose(f);
    return CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
}

#pragma mark - 快照

static CFDictionaryRef gInfo;   // 最近一次元数据
static int gPID;
static Boolean gPlaying;
static char gLastJSON[8192];

static void emit(Boolean force);

static void refreshAndEmit(Boolean force) {
    if (!loadMediaRemote()) { fputs("null\n", stdout); fflush(stdout); return; }
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block CFDictionaryRef info = NULL;
    __block int pid = 0;
    __block Boolean playing = false;

    dispatch_semaphore_t s1 = dispatch_semaphore_create(0);
    dispatch_semaphore_t s2 = dispatch_semaphore_create(0);
    dispatch_semaphore_t s3 = dispatch_semaphore_create(0);

    if (gGetInfo) gGetInfo(q, ^(CFDictionaryRef i) { info = i ? CFRetain(i) : NULL; dispatch_semaphore_signal(s1); });
    else dispatch_semaphore_signal(s1);
    if (gGetPID) gGetPID(q, ^(int p) { pid = p; dispatch_semaphore_signal(s2); });
    else dispatch_semaphore_signal(s2);
    if (gGetPlaying) gGetPlaying(q, ^(Boolean p) { playing = p; dispatch_semaphore_signal(s3); });
    else dispatch_semaphore_signal(s3);

    dispatch_semaphore_wait(s1, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    dispatch_semaphore_wait(s2, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    dispatch_semaphore_wait(s3, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    (void)sem;

    if (gInfo) { CFRelease(gInfo); gInfo = NULL; }
    gInfo = info;
    gPID = pid;
    gPlaying = playing;
    emit(force);
}

static void emit(Boolean force) {
    char buf[8192];
    FILE *out = fmemopen(buf, sizeof(buf) - 1, "w");
    if (!out) return;

    CFDictionaryRef info = gInfo;
    fputc('{', out);
    fputs("\"title\":", out);      putEscaped(out, info ? strFrom(info, gKeyTitle) : NULL); fputc(',', out);
    fputs("\"artist\":", out);     putEscaped(out, info ? strFrom(info, gKeyArtist) : NULL); fputc(',', out);
    fputs("\"album\":", out);      putEscaped(out, info ? strFrom(info, gKeyAlbum) : NULL); fputc(',', out);
    fprintf(out, "\"duration\":%.3f,", info ? numFrom(info, gKeyDuration) : 0.0);
    fprintf(out, "\"elapsed\":%.3f,", info ? numFrom(info, gKeyElapsed) : 0.0);
    fprintf(out, "\"rate\":%.2f,", info ? numFrom(info, gKeyRate) : 0.0);
    fprintf(out, "\"pid\":%d,", gPID);
    fprintf(out, "\"playing\":%s,", gPlaying ? "true" : "false");
    fputs("\"artwork\":", out);
    CFStringRef art = writeArtwork(info);
    putEscaped(out, art);
    if (art) CFRelease(art);
    fputc('}', out);
    fputc('\n', out);
    fflush(out);
    long n = ftell(out);
    fclose(out);
    if (n <= 0) return;
    buf[n] = '\0';
    if (!force && strcmp(buf, gLastJSON) == 0) return;
    strncpy(gLastJSON, buf, sizeof(gLastJSON) - 1);
    fputs(buf, stdout);
    fflush(stdout);
}

#pragma mark - 导出

// 宿主进程被强杀时，perl 会变成孤儿常驻。这里盯住父进程，父进程没了就退出。
static void startParentWatch(void) {
    pid_t parent = getppid();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        for (;;) {
            sleep(2);
            if (getppid() != parent) _exit(0);
        }
    });
}

void mr_run(void) {
    if (!loadMediaRemote()) { fputs("null\n", stdout); fflush(stdout); return; }
    refreshAndEmit(true);
}

// 刷新统一串行化，避免多线程同时写 stdout / 改 gInfo
static dispatch_queue_t gRefreshQueue;
static int gHeartbeat;

static void scheduleRefresh(void) {
    if (!gRefreshQueue) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), gRefreshQueue, ^{
        @autoreleasepool { refreshAndEmit(false); }
    });
}

void mr_stream(void) {
    if (!loadMediaRemote()) { fputs("null\n", stdout); fflush(stdout); return; }
    startParentWatch();

    gRefreshQueue = dispatch_queue_create("com.flyisland.media.refresh", DISPATCH_QUEUE_SERIAL);
    gHeartbeat = getenv("MR_HEARTBEAT") != NULL;
    if (gRegister) gRegister(gRefreshQueue);

    NSDistributedNotificationCenter *dc = [NSDistributedNotificationCenter defaultCenter];
    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingInfoPlaybackRateDidChangeNotification",
    ];
    for (NSString *name in names) {
        [dc addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
            scheduleRefresh();
        }];
    }

    dispatch_sync(gRefreshQueue, ^{ refreshAndEmit(true); });

    // 兜底轮询：多数播放器不发分布式通知，靠这个保证状态新鲜
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gRefreshQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 1 * NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        @autoreleasepool {
            if (gHeartbeat) { fprintf(stderr, "tick\n"); fflush(stderr); }
            refreshAndEmit(false);
        }
    });
    dispatch_resume(timer);

    // 只用来接收分布式通知，刷新本身不依赖 run loop
    CFRunLoopRun();
}

// 调试：把 NowPlaying info 的全部字段打出来（找歌词等字段用）
void mr_dump(void) {
    if (!loadMediaRemote()) { fputs("null\n", stdout); return; }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block CFDictionaryRef info = NULL;
    gGetInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(CFDictionaryRef i) {
        info = i ? CFRetain(i) : NULL;
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    if (!info) { fputs("null\n", stdout); return; }
    CFIndex n = CFDictionaryGetCount(info);
    const void **keys = malloc(sizeof(void *) * n);
    const void **vals = malloc(sizeof(void *) * n);
    CFDictionaryGetKeysAndValues(info, keys, vals);
    for (CFIndex i = 0; i < n; i++) {
        CFStringRef k = (CFStringRef)keys[i];
        CFTypeRef v = vals[i];
        char kb[512] = {0};
        if (k) CFStringGetCString(k, kb, sizeof(kb), kCFStringEncodingUTF8);
        CFTypeID t = CFGetTypeID(v);
        if (t == CFStringGetTypeID()) {
            char vb[1024] = {0};
            CFStringGetCString((CFStringRef)v, vb, sizeof(vb), kCFStringEncodingUTF8);
            printf("%s = STR \"%s\"\n", kb, vb);
        } else if (t == CFDataGetTypeID()) {
            printf("%s = DATA %ld bytes\n", kb, (long)CFDataGetLength((CFDataRef)v));
        } else if (t == CFNumberGetTypeID()) {
            double d = 0;
            CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
            printf("%s = NUM %.3f\n", kb, d);
        } else {
            printf("%s = OTHER typeid=%lu\n", kb, (unsigned long)t);
        }
    }
    free(keys);
    free(vals);
    CFRelease(info);
}

void mr_command(void) {
    if (!loadMediaRemote()) { fputs("null\n", stdout); fflush(stdout); return; }
    const char *raw = getenv("MR_COMMAND");
    int cmd = raw ? atoi(raw) : 2;
    Boolean ok = gSendCommand(cmd, NULL);
    printf("{\"ok\":%s,\"cmd\":%d}\n", ok ? "true" : "false", cmd);
    fflush(stdout);
}
