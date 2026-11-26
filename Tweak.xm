#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <stdarg.h>

#define KZ_DOMAIN @"com.minis.kztheme"
#define KZ_NOTIFY "com.minis.kztheme.changed"
#define KZ_THEME_DIR @"/Library/KZTheme"
#define KZ_LOG @"/var/mobile/Library/KZTheme.log"

static NSString *KZStr(NSString *key, NSString *dflt) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)KZ_DOMAIN);
    if (v) { NSString *s = [NSString stringWithFormat:@"%@", (__bridge id)v]; CFRelease(v); return s; }
    return dflt;
}

static double KZNum(NSString *key, double dflt) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)KZ_DOMAIN);
    if (v) { double d = [(__bridge NSNumber *)v doubleValue]; CFRelease(v); return d; }
    return dflt;
}

static void KZLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], body];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attr = [fm attributesOfItemAtPath:KZ_LOG error:nil];
    if ([attr fileSize] > 96 * 1024) [line writeToFile:KZ_LOG atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:KZ_LOG];
    if (!fh) { [line writeToFile:KZ_LOG atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    else { @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; } @catch (...) {} }
}

// 录屏指示器所在的 app 可能出现在这几个位置（有无根 / bindfs 挂载 / 直连）
static NSArray<NSString *> *KZAppRoots(void) {
    return @[ @"/Applications/ReplayKitAngel.app",
              @"/var/jb/mnt/Applications/ReplayKitAngel.app",
              @"/mnt/Applications/ReplayKitAngel.app",
              @"/var/jb/Applications/ReplayKitAngel.app",
              @"/rootfs/Applications/ReplayKitAngel.app" ];
}

// 返回 @{@"root": 实际用的 app 路径, @"dirs": .ca 目录数组}
static NSDictionary *KZFindCADirs(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in KZAppRoots()) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;
        NSArray *items = [fm contentsOfDirectoryAtPath:root error:nil];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *name in items) {
            if (![name hasSuffix:@".ca"]) continue;
            if (![name hasPrefix:@"sc_compact_"]) continue;
            [out addObject:[root stringByAppendingPathComponent:name]];
        }
        if (out.count > 0) return @{ @"root": root, @"dirs": out };
    }
    return @{ @"root": @"(none)", @"dirs": @[] };
}

static BOOL KZWriteData(NSData *data, NSString *path) {
    NSError *err = nil;
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&err];
    if (!ok) KZLog(@"write FAILED %@ : %@", path, err.localizedDescription ?: @"?");
    return ok;
}

static NSData *KZEyePNG(NSString *eyeName) {
    if ([eyeName isEqualToString:@"custom"]) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("eyeImage"), (__bridge CFStringRef)KZ_DOMAIN);
        if (v) {
            NSString *b64 = [NSString stringWithFormat:@"%@", (__bridge id)v];
            CFRelease(v);
            NSData *d = [[NSData alloc] initWithBase64EncodedString:b64
                                                            options:NSDataBase64DecodingIgnoreUnknownCharacters];
            if (d.length > 200) return d;
            KZLog(@"custom image decode failed (len=%lu)", (unsigned long)b64.length);
        } else {
            KZLog(@"custom image missing in prefs");
        }
    }
    NSString *p = [KZ_THEME_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"eye/%@.png", eyeName]];
    NSData *d = [NSData dataWithContentsOfFile:p];
    if (d) return d;
    return [NSData dataWithContentsOfFile:[KZ_THEME_DIR stringByAppendingPathComponent:@"eye/sharingan.png"]];
}

static void KZApply(void) {
    NSString *eyeName = KZStr(@"eye", @"sharingan");
    NSString *cdStyle = KZStr(@"countdown", @"B");
    double scale = KZNum(@"scale", 0.6);
    double dur = KZNum(@"duration", 1.5);
    if (scale < 0.05) scale = 0.6;
    if (scale > 1.4) scale = 1.4;
    if (dur < 0.1) dur = 1.5;

    NSDictionary *found = KZFindCADirs();
    NSArray *dirs = found[@"dirs"];
    if (dirs.count == 0) {
        KZLog(@"apply: no .ca dirs (theme=%@ eye=%@) — 挂载可能没加", KZ_THEME_DIR, eyeName);
        return;
    }

    NSData *eyePNG = KZEyePNG(eyeName);
    NSData *dotPNG = [NSData dataWithContentsOfFile:[KZ_THEME_DIR stringByAppendingPathComponent:@"eye/dot.png"]];
    NSMutableArray *cdPNG = [NSMutableArray array];
    NSString *cdDir = [KZ_THEME_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"cd/%@", cdStyle]];
    for (int i = 1; i <= 3; i++) {
        NSData *d = [NSData dataWithContentsOfFile:
                     [cdDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]]];
        [cdPNG addObject:d ?: [NSData data]];
    }
    if (!eyePNG) KZLog(@"apply: eye image missing (%@)", eyeName);

    NSString *scaleStr = [NSString stringWithFormat:@"%.5f", scale];
    NSString *durStr = [NSString stringWithFormat:@"%.3f", dur];

    int ok = 0;
    for (NSString *dir in dirs) {
        NSString *tplPath = [dir.lastPathComponent containsString:@"minimal"] ? @"min.caml" : @"lead.caml";
        NSString *tpl = [NSString stringWithContentsOfFile:[KZ_THEME_DIR stringByAppendingPathComponent:tplPath]
                                                  encoding:NSUTF8StringEncoding error:nil];
        if (!tpl) { KZLog(@"apply: template %@ missing", tplPath); continue; }
        NSString *caml = [tpl stringByReplacingOccurrencesOfString:@"__SCALE__" withString:scaleStr];
        caml = [caml stringByReplacingOccurrencesOfString:@"__DUR__" withString:durStr];

        BOOL good = KZWriteData([caml dataUsingEncoding:NSUTF8StringEncoding],
                                [dir stringByAppendingPathComponent:@"main.caml"]);
        if (eyePNG) good = KZWriteData(eyePNG, [dir stringByAppendingPathComponent:@"shar.png"]) && good;
        if (dotPNG) KZWriteData(dotPNG, [dir stringByAppendingPathComponent:@"dot.png"]);
        for (int i = 1; i <= 3; i++) {
            NSData *d = cdPNG[i - 1];
            if (d.length > 0)
                KZWriteData(d, [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]]);
        }
        if (good) ok++;
    }

    // 清掉旧版遗留的多余 png
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        for (NSString *p in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if (![p hasSuffix:@".png"]) continue;
            if ([p isEqualToString:@"shar.png"] || [p isEqualToString:@"dot.png"] ||
                [p isEqualToString:@"1.png"] || [p isEqualToString:@"2.png"] || [p isEqualToString:@"3.png"]) continue;
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:p] error:nil];
        }
    }
    KZLog(@"apply: root=%@ dirs=%lu ok=%d eye=%@ cd=%@ scale=%@ dur=%@",
          found[@"root"], (unsigned long)dirs.count, ok, eyeName, cdStyle, scaleStr, durStr);
}


static void KZNotifyCallback(CFNotificationCenterRef c, void *observer, CFStringRef name,
                             const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ KZApply(); });
}

%ctor {
    KZLog(@"tweak loaded (v1.1.0)");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KZApply();
    });
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    KZNotifyCallback, CFSTR(KZ_NOTIFY), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
