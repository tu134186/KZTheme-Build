#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>

#define KZ_DOMAIN @"com.minis.kztheme"
#define KZ_NOTIFY "com.minis.kztheme.changed"
#define KZ_THEME_DIR @"/Library/Application Support/KZTheme"
#define KZ_REPLAY_APP @"/Applications/ReplayKitAngel.app"

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

// 扫描 ReplayKitAngel.app 里所有录屏用的 .ca 目录，自动适配设备代号（-D73 / -D74 ...）
static NSArray<NSString *> *KZRecordingCADirs(void) {
    NSMutableArray *out = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:KZ_REPLAY_APP error:nil];
    for (NSString *name in items) {
        if (![name hasSuffix:@".ca"]) continue;
        if (![name hasPrefix:@"sc_compact_"]) continue;
        [out addObject:[KZ_REPLAY_APP stringByAppendingPathComponent:name]];
    }
    return out;
}

static BOOL KZWriteString(NSString *text, NSString *path) {
    return [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES];
}

static void KZLog(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[KZTheme] %@\n", msg];
    NSString *p = @"/var/mobile/Library/KZTheme.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!fh) { [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    else { @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; } @catch (...) {} }
}

static void KZApply(void) {
    NSString *eyeName = KZStr(@"eye", @"sharingan");
    NSString *cdStyle = KZStr(@"countdown", @"B");
    double scale = KZNum(@"scale", 0.6);
    double dur = KZNum(@"duration", 1.5);
    if (scale < 0.2) scale = 0.2;
    if (scale > 1.4) scale = 1.4;
    if (dur < 0.2) dur = 0.2;

    NSString *themeDir = KZ_THEME_DIR;
    NSString *eyeSrc = [themeDir stringByAppendingPathComponent:[NSString stringWithFormat:@"eye/%@.png", eyeName]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:eyeSrc])
        eyeSrc = [themeDir stringByAppendingPathComponent:@"eye/sharingan.png"];

    NSString *cdDir = [themeDir stringByAppendingPathComponent:[NSString stringWithFormat:@"cd/%@", cdStyle]];

    NSArray *dirs = KZRecordingCADirs();
    if (dirs.count == 0) { KZLog(@"no .ca dirs found (mount missing?)"); return; }

    NSString *scaleStr = [NSString stringWithFormat:@"%.5f", scale];
    NSString *durStr = [NSString stringWithFormat:@"%.3f", dur];

    int ok = 0;
    for (NSString *dir in dirs) {
        // 1) 生成 main.caml
        NSString *tplPath = [dir.lastPathComponent containsString:@"minimal"] ? @"min.caml" : @"lead.caml";
        NSString *tpl = [NSString stringWithContentsOfFile:[themeDir stringByAppendingPathComponent:tplPath]
                                                  encoding:NSUTF8StringEncoding error:nil];
        if (!tpl) continue;
        NSString *caml = [tpl stringByReplacingOccurrencesOfString:@"__SCALE__" withString:scaleStr];
        caml = [caml stringByReplacingOccurrencesOfString:@"__DUR__" withString:durStr];
        NSString *dst = [dir stringByAppendingPathComponent:@"main.caml"];
        if (!KZWriteString(caml, dst)) { KZLog([NSString stringWithFormat:@"write failed: %@", dst]); continue; }

        // 2) 素材
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:@"shar.png"] error:nil];
        [fm copyItemAtPath:eyeSrc toPath:[dir stringByAppendingPathComponent:@"shar.png"] error:nil];
        [fm copyItemAtPath:[themeDir stringByAppendingPathComponent:@"eye/dot.png"]
                    toPath:[dir stringByAppendingPathComponent:@"dot.png"] error:nil];
        for (int i = 1; i <= 3; i++) {
            NSString *src = [cdDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]] error:nil];
            [fm copyItemAtPath:src toPath:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]] error:nil];
        }
        ok++;
    }
    KZLog([NSString stringWithFormat:@"applied eye=%@ cd=%@ scale=%@ dur=%@ -> %d dirs", eyeName, cdStyle, scaleStr, durStr, ok]);

    // 3) 清掉旧版遗留的多余 png（86 张那批）
    for (NSString *dir in dirs) {
        NSArray *pngs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *p in pngs) {
            if (![p hasSuffix:@".png"]) continue;
            if ([p isEqualToString:@"shar.png"] || [p isEqualToString:@"dot.png"] ||
                [p isEqualToString:@"1.png"] || [p isEqualToString:@"2.png"] || [p isEqualToString:@"3.png"]) continue;
            [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:p] error:nil];
        }
    }
}


static void KZNotifyCallback(CFNotificationCenterRef c, void *observer, CFStringRef name,
                             const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ KZApply(); });
}

%ctor {
    KZLog(@"tweak loaded");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KZApply();
    });
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    KZNotifyCallback, CFSTR(KZ_NOTIFY), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}