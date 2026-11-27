#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define KZ_DOMAIN @"com.minis.kztheme"
#define KZ_NOTIFY "com.minis.kztheme.changed"

static NSString *KZPrefStr(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)KZ_DOMAIN);
    if (!v) return nil;
    NSString *s = [NSString stringWithFormat:@"%@", (__bridge id)v];
    CFRelease(v);
    return s;
}

static void KZPrefSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)KZ_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)KZ_DOMAIN);
}

static void KZPrefClear(NSString *key) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)KZ_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)KZ_DOMAIN);
}

// 拖动滑块会连续写值，去抖 0.8 秒只应用最后那一次
static void KZApplySoon(void) {
    static int gen = 0;
    gen++;
    int mine = gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (mine == gen) notify_post(KZ_NOTIFY);
    });
}

@interface PSListController (KZPrivate)
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

@interface KZRootListController : PSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation KZRootListController

#pragma mark - 规格

- (id)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self decorate:_specifiers];
    }
    return _specifiers;
}

- (void)decorate:(NSArray *)list {
    for (PSSpecifier *s in list) {
        if ([s propertyForKey:@"action"]) [s setTarget:self];
        NSString *key = [s propertyForKey:@"key"];
        if (!key) continue;
        if ([key isEqualToString:@"eyeName"]) {
            NSString *eye = KZPrefStr(@"eye") ?: @"sharingan";
            NSString *shown = [eye isEqualToString:@"custom"] ? @"自定义图片" : eye;
            [s setName:[NSString stringWithFormat:@"当前素材：%@", shown]];
        } else if ([key isEqualToString:@"countdown"]) {
            NSDictionary *names = @{ @"A": @"A 六边形白点", @"B": @"B 彩色数字", @"C": @"C 彩色秒表" };
            NSString *cd = KZPrefStr(@"countdown") ?: @"B";
            [s setName:[NSString stringWithFormat:@"样式：%@", names[cd] ?: cd]];
        } else if ([key isEqualToString:@"kzStatus"]) {
            [s setName:[self statusText]];
        } else if ([key isEqualToString:@"kzResult"]) {
            NSString *res = KZPrefStr(@"lastResult") ?: @"无记录";
            [s setName:[NSString stringWithFormat:@"上次应用：%@", res]];
        } else if ([key isEqualToString:@"scale"]) {
            [s setName:[NSString stringWithFormat:@"大小 %.2f", [self numPref:@"scale" dflt:0.6]]];
        } else if ([key isEqualToString:@"duration"]) {
            [s setName:[NSString stringWithFormat:@"转速 %.2f 秒", [self numPref:@"duration" dflt:1.5]]];
        }
    }
}

- (double)numPref:(NSString *)key dflt:(double)d {
    NSString *s = KZPrefStr(key);
    if (!s) return d;
    double v = [s doubleValue];
    return v > 0 ? v : d;
}

- (NSString *)statusText {
    NSString *seen = KZPrefStr(@"lastSeen");
    if (!seen) return @"插件：未运行（tweak 没被注入，或刚重启不到 3 秒）";
    double d = [[NSDate date] timeIntervalSince1970] - [seen doubleValue];
    NSString *ago = d < 90 ? @"刚刚" : [NSString stringWithFormat:@"%.0f 分钟前", d / 60.0];
    return [NSString stringWithFormat:@"插件：运行中（%@）", ago];
}

- (void)refreshRows {
    [self decorate:self.specifiers];
    [self.tableView reloadData];
}

#pragma mark - 偏好读写

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    KZPrefSet(key, value);
    KZApplySoon();
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = key ? KZPrefStr(key) : nil;
    if (!v) v = [specifier propertyForKey:@"default"];
    return v;
}

#pragma mark - 素材

- (void)storeImage:(UIImage *)img {
    if (!img || !img.CGImage) return;
    UIImage *norm = img;
    if (img.imageOrientation != UIImageOrientationUp) {
        UIGraphicsBeginImageContextWithOptions(img.size, NO, 1.0);
        [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
        norm = UIGraphicsGetImageFromCurrentImageContext() ?: img;
        UIGraphicsEndImageContext();
    }
    CGImageRef cg = norm.CGImage;
    if (!cg) return;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    size_t side = w < h ? w : h;
    CGImageRef square = CGImageCreateWithImageInRect(cg, CGRectMake((double)(w - side) / 2.0,
                                                                   (double)(h - side) / 2.0,
                                                                   (double)side, (double)side));
    if (!square) return;
    UIImage *sq = [UIImage imageWithCGImage:square scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(square);

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(320, 320), NO, 1.0);
    [sq drawInRect:CGRectMake(0, 0, 320, 320)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *png = UIImagePNGRepresentation(scaled ?: sq);
    if (!png) return;

    KZPrefSet(@"eyeImage", [png base64EncodedStringWithOptions:0]);
    KZPrefSet(@"eye", @"custom");
    notify_post(KZ_NOTIFY);
    [self refreshRows];
    [self alert:@"已导入" msg:@"已经存为当前素材，开始录屏就能看到。"];
}

- (void)alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)importPhoto {
    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        [self storeImage:img];
    }];
}

- (void)importFile {
    UIDocumentPickerViewController *dp =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypePNG, UTTypeImage ]];
    dp.delegate = self;
    dp.allowsMultipleSelection = NO;
    [self presentViewController:dp animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    BOOL access = [u startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:u];
    if (access) [u stopAccessingSecurityScopedResource];
    if (data) [self storeImage:[UIImage imageWithData:data]];
}

- (void)resetEye {
    KZPrefSet(@"eye", @"sharingan");
    KZPrefClear(@"eyeImage");
    notify_post(KZ_NOTIFY);
    [self refreshRows];
}

#pragma mark - 样式 / 数值

- (void)cycleCountdown {
    NSArray *vals = @[ @"A", @"B", @"C" ];
    NSString *cur = KZPrefStr(@"countdown") ?: @"B";
    NSUInteger i = [vals indexOfObject:cur];
    NSUInteger next = (i == NSNotFound) ? 1 : (i + 1) % vals.count;
    KZPrefSet(@"countdown", vals[next]);
    notify_post(KZ_NOTIFY);
    [self refreshRows];
}

- (void)bump:(NSString *)key delta:(double)delta min:(double)mn max:(double)mx dflt:(double)dflt {
    double v = [self numPref:key dflt:dflt] + delta;
    if (v < mn) v = mn;
    if (v > mx) v = mx;
    KZPrefSet(key, [NSString stringWithFormat:@"%.2f", v]);
    notify_post(KZ_NOTIFY);
    [self refreshRows];
}

- (void)scaleDown { [self bump:@"scale" delta:-0.05 min:0.10 max:0.60 dflt:0.6]; }
- (void)scaleUp   { [self bump:@"scale" delta:+0.05 min:0.10 max:0.60 dflt:0.6]; }
- (void)durDown   { [self bump:@"duration" delta:-0.1 min:0.2 max:5.0 dflt:1.5]; }
- (void)durUp     { [self bump:@"duration" delta:+0.1 min:0.2 max:5.0 dflt:1.5]; }

- (void)promptNumberForKey:(NSString *)key title:(NSString *)title min:(double)mn max:(double)mx {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = KZPrefStr(key);
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        double v = [a.textFields.firstObject.text doubleValue];
        if (v < mn) v = mn;
        if (v > mx) v = mx;
        KZPrefSet(key, [NSString stringWithFormat:@"%.2f", v]);
        notify_post(KZ_NOTIFY);
        [self refreshRows];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editScale { [self promptNumberForKey:@"scale" title:@"大小（0.10 - 0.60）" min:0.10 max:0.60]; }
- (void)editDuration { [self promptNumberForKey:@"duration" title:@"转速秒数（0.2 - 5.0）" min:0.2 max:5.0]; }

- (void)applyNow {
    notify_post(KZ_NOTIFY);
    [self refreshRows];
    [self alert:@"已应用" msg:@"设置已经写进挂载目录。开始录屏就能看到；如果没变化，去 Dopamine 注销一次。"];
}

@end
