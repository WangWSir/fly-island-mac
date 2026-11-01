#!/usr/bin/perl
# MediaRemote 适配器宿主。
#
# macOS 15.4 起 mediaremoted 只对 bundle id 为 com.apple.* 的进程放行 NowPlaying，
# 第三方 app 直接调用一律拿到空数据。/usr/bin/perl 的 bundle id 是 com.apple.perl，
# 由它加载动态库后，调用就发生在有权限的进程里。
#
# 用法：
#   MR_LIB=<dylib> MR_FN=mr_stream  perl mediaremote.pl    # 长驻输出
#   MR_LIB=<dylib> MR_FN=mr_run     perl mediaremote.pl    # 取一次
#   MR_LIB=<dylib> MR_FN=mr_command MR_COMMAND=2 perl mediaremote.pl

use strict;
use warnings;
use DynaLoader;

$| = 1;
binmode(STDOUT, ':utf8');

my $lib = $ENV{'MR_LIB'} or do { print "null\n"; exit 1 };
my $fn  = $ENV{'MR_FN'} || 'mr_stream';

# 不向 stdout 输出任何非数据内容，否则会污染 JSON 流
open(my $err, '>&', \*STDERR);

my $handle = DynaLoader::dl_load_file($lib, 0) or do {
    print $err "perl adapter: load failed $lib\n";
    print "null\n";
    exit 1;
};

my $symaddr = DynaLoader::dl_find_symbol($handle, $fn) or do {
    print $err "perl adapter: symbol not found $fn\n";
    print "null\n";
    exit 1;
};

my $entry = DynaLoader::dl_install_xsub("main::$fn", $symaddr, $lib);
$entry->();
