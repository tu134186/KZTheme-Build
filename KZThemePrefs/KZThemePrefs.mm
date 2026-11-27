#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
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

@interface PSSpecifier (KZPrivate)
- (id)performGetter;
- (void)performSetterWithValue:(id)value;
- (void)setCellClass:(Class)cls;
@end

@interface PSListController (KZPrivate)
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

@interface KZRootListController : PSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@end


#pragma mark - 一条杠：－ 滑块 ＋

@interface KZStepperCell : PSTableCell
@end

@implementation KZStepperCell {
    UISlider *_slider;
    UILabel *_name;
    UILabel *_value;
    UIButton *_minus;
    UIButton *_plus;
    double _min, _max, _step;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _min = [[specifier propertyForKey:@"min"] doubleValue];
        _max = [[specifier propertyForKey:@"max"] doubleValue];
        _step = [[specifier propertyForKey:@"step"] doubleValue];
        if (_step <= 0) _step = 0.05;
        if (_max <= _min) { _min = 0; _max = 1; }

        _name = [[UILabel alloc] init];
        _name.font = [UIFont systemFontOfSize:13];
        _name.textColor = [UIColor secondaryLabelColor];
        _name.text = [specifier propertyForKey:@"kzTitle"] ?: [specifier propertyForKey:@"label"];

        _value = [[UILabel alloc] init];
        _value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
        _value.textAlignment = NSTextAlignmentRight;

        _slider = [[UISlider alloc] init];
        _slider.minimumValue = (float)_min;
        _slider.maximumValue = (float)_max;
        [_slider addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];

        _minus = [self stepButton:@"\u2212"];
        [_minus addTarget:self action:@selector(stepDown) forControlEvents:UIControlEventTouchUpInside];
        _plus = [self stepButton:@"+"];
        [_plus addTarget:self action:@selector(stepUp) forControlEvents:UIControlEventTouchUpInside];

        for (UIView *v in @[ _name, _value, _slider, _minus, _plus ]) [self.contentView addSubview:v];
        [self refreshCellContentsWithSpecifier:specifier];
    }
    return self;
}

- (UIButton *)stepButton:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightMedium];
    b.backgroundColor = [UIColor secondarySystemBackgroundColor];
    b.layer.cornerRadius = 7;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    return b;
}

- (double)currentValue {
    id v = [self.specifier performGetter];
    if (!v) v = [self.specifier propertyForKey:@"default"];
    double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : _min;
    if (d < _min) d = _min;
    if (d > _max) d = _max;
    return d;
}

- (void)writeValue:(double)v {
    if (v < _min) v = _min;
    if (v > _max) v = _max;
    [self.specifier performSetterWithValue:@(v)];
    _slider.value = (float)v;
    _value.text = [NSString stringWithFormat:@"%.2f", v];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    if (!_slider) return;
    double d = [self currentValue];
    _slider.value = (float)d;
    _value.text = [NSString stringWithFormat:@"%.2f", d];
    _name.text = [specifier propertyForKey:@"kzTitle"] ?: [specifier propertyForKey:@"label"];
}

- (void)sliderMoved:(UISlider *)s {
    double v = round(s.value / _step) * _step;
    [self writeValue:v];
}

- (void)stepDown { [self writeValue:[self currentValue] - _step]; }
- (void)stepUp   { [self writeValue:[self currentValue] + _step]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat w = b.size.width, h = b.size.height;
    _name.frame = CGRectMake(16, 7, w - 150, 18);
    _value.frame = CGRectMake(w - 112, 7, 96, 18);
    _minus.frame = CGRectMake(12, h - 36, 36, 28);
    _plus.frame = CGRectMake(w - 48, h - 36, 36, 28);
    _slider.frame = CGRectMake(54, h - 36, w - 108, 28);
}

@end


#pragma mark - 样式选择页（点进去选 A/B/C，选中打勾）

@interface KZPickerController : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray<NSString *> *values;
@property (nonatomic, copy) NSString *current;
@property (nonatomic, copy) void (^onPick)(NSString *value);
@end

@implementation KZPickerController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.titles.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return @"倒数 3-2-1 样式";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"kzpick";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    cell.textLabel.text = self.titles[ip.row];
    BOOL on = [self.values[ip.row] isEqualToString:self.current];
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *v = self.values[ip.row];
    self.current = v;
    [tv reloadData];
    if (self.onPick) self.onPick(v);
}

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

- (double)numPref:(NSString *)key dflt:(double)d {
    NSString *s = KZPrefStr(key);
    if (!s) return d;
    double v = [s doubleValue];
    return v > 0 ? v : d;
}

- (NSString *)eyeShown {
    NSString *eye = KZPrefStr(@"eye") ?: @"sharingan";
    return [eye isEqualToString:@"custom"] ? @"自定义图片" : eye;
}

- (NSString *)cdName {
    NSDictionary *names = @{ @"A": @"A 六边形白点", @"B": @"B 彩色数字", @"C": @"C 彩色秒表" };
    NSString *cd = KZPrefStr(@"countdown") ?: @"B";
    return names[cd] ?: cd;
}

- (NSString *)statusText {
    NSString *seen = KZPrefStr(@"lastSeen");
    if (!seen) return @"插件：未运行（tweak 没被注入，或刚重启不到 3 秒）";
    double d = [[NSDate date] timeIntervalSince1970] - [seen doubleValue];
    NSString *ago = d < 90 ? @"刚刚" : [NSString stringWithFormat:@"%.0f 分钟前", d / 60.0];
    return [NSString stringWithFormat:@"插件：运行中（%@）", ago];
}

- (void)decorate:(NSArray *)list {
    for (PSSpecifier *s in list) {
        if ([s propertyForKey:@"action"]) [s setTarget:self];
        NSString *key = [s propertyForKey:@"key"];
        if (!key) continue;
        if ([key isEqualToString:@"eyeName"]) {
            [s setName:[NSString stringWithFormat:@"当前素材：%@", [self eyeShown]]];
        } else if ([key isEqualToString:@"countdown"]) {
            [s setName:[NSString stringWithFormat:@"样式：%@（点这里选）", [self cdName]]];
        } else if ([key isEqualToString:@"kzStatus"]) {
            [s setName:[self statusText]];
        } else if ([key isEqualToString:@"kzResult"]) {
            NSString *res = KZPrefStr(@"lastResult") ?: @"无记录";
            [s setName:[NSString stringWithFormat:@"上次应用：%@", res]];
        } else if ([key isEqualToString:@"scale"] || [key isEqualToString:@"duration"]) {
            Class stepper = NSClassFromString(@"KZStepperCell");
            if (stepper) {
                [s setProperty:stepper forKey:@"cellClass"];
                if ([s respondsToSelector:@selector(setCellClass:)]) [s setCellClass:stepper];
            }
            [s setProperty:@62 forKey:@"height"];
        } else if ([key isEqualToString:@"kzValues"]) {
            [s setName:[NSString stringWithFormat:@"当前：大小 %.2f ｜ 转速 %.2f 秒 ｜ 样式 %@",
                        [self numPref:@"scale" dflt:0.6], [self numPref:@"duration" dflt:1.5],
                        [self cdName]]];
        }
    }
}

- (void)refreshRows {
    [self decorate:self.specifiers];
    [self.tableView reloadData];
}

#pragma mark - 反馈

- (void)toast:(NSString *)msg {
    UIView *host = self.view;
    if (!host) return;
    [[host viewWithTag:9091] removeFromSuperview];

    UILabel *l = [[UILabel alloc] init];
    l.tag = 9091;
    l.text = msg;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    l.layer.cornerRadius = 13;
    l.layer.masksToBounds = YES;
    l.alpha = 0;

    CGFloat maxW = host.bounds.size.width - 56;
    l.frame = CGRectMake(0, 0, maxW, 44);
    [l sizeToFit];
    CGSize sz = l.frame.size;
    CGFloat w = MIN(sz.width + 34, maxW);
    CGFloat h = sz.height + 18;
    l.frame = CGRectMake((host.bounds.size.width - w) / 2,
                         host.bounds.size.height - 160,
                         w, h);
    [host addSubview:l];
    [host bringSubviewToFront:l];

    [UIView animateWithDuration:0.12 animations:^{
        l.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.35 delay:1.15 options:0 animations:^{
            l.alpha = 0.0;
        } completion:^(BOOL done) {
            [l removeFromSuperview];
        }];
    }];
}

#pragma mark - 偏好读写

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    KZPrefSet(key, value);
    KZApplySoon();
    [self decorate:self.specifiers];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = key ? KZPrefStr(key) : nil;
    if (!v) v = [specifier propertyForKey:@"default"];
    return v;
}

#pragma mark - 素材

- (void)storeImage:(UIImage *)img {
    if (!img || !img.CGImage) {
        [self toast:@"这张图读不出来，换一张试试"];
        return;
    }
    UIImage *norm = img;
    if (img.imageOrientation != UIImageOrientationUp) {
        UIGraphicsBeginImageContextWithOptions(img.size, NO, 1.0);
        [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
        norm = UIGraphicsGetImageFromCurrentImageContext() ?: img;
        UIGraphicsEndImageContext();
    }
    CGImageRef cg = norm.CGImage;
    if (!cg) { [self toast:@"这张图读不出来，换一张试试"]; return; }
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    size_t side = w < h ? w : h;
    CGImageRef square = CGImageCreateWithImageInRect(cg, CGRectMake((double)(w - side) / 2.0,
                                                                   (double)(h - side) / 2.0,
                                                                   (double)side, (double)side));
    if (!square) { [self toast:@"这张图读不出来，换一张试试"]; return; }
    UIImage *sq = [UIImage imageWithCGImage:square scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(square);

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(320, 320), NO, 1.0);
    [sq drawInRect:CGRectMake(0, 0, 320, 320)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *png = UIImagePNGRepresentation(scaled ?: sq);
    if (!png) { [self toast:@"这张图存不下来，换一张试试"]; return; }

    KZPrefSet(@"eyeImage", [png base64EncodedStringWithOptions:0]);
    KZPrefSet(@"eye", @"custom");
    notify_post(KZ_NOTIFY);
    [self refreshRows];
    [self toast:@"已导入，正在应用…"];
    [self toastResultLater];
}

- (void)importPhoto {
    [self toast:@"打开相册…"];
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

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        [self toast:@"取消了，没有改动"];
    }];
}

- (void)importFile {
    [self toast:@"打开文件…"];
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
    else [self toast:@"这个文件读不出来"];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self toast:@"取消了，没有改动"];
}

- (void)resetEye {
    KZPrefSet(@"eye", @"sharingan");
    KZPrefClear(@"eyeImage");
    notify_post(KZ_NOTIFY);
    [self refreshRows];
    [self toast:@"已恢复默认写轮眼"];
    [self toastResultLater];
}

#pragma mark - 样式 / 数值

- (void)pickCountdown {
    KZPickerController *p = [[KZPickerController alloc] init];
    p.title = @"倒数 3-2-1 样式";
    p.titles = @[ @"A 六边形白点", @"B 彩色数字", @"C 彩色秒表" ];
    p.values = @[ @"A", @"B", @"C" ];
    p.current = KZPrefStr(@"countdown") ?: @"B";
    __weak typeof(self) weakSelf = self;
    p.onPick = ^(NSString *v) {
        KZPrefSet(@"countdown", v);
        notify_post(KZ_NOTIFY);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf refreshRows];
            [weakSelf toast:[NSString stringWithFormat:@"样式已换成 %@", [weakSelf cdName]]];
        });
    };
    [self.navigationController pushViewController:p animated:YES];
}

#pragma mark - 应用

- (void)toastResultLater {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshRows];
        NSString *res = KZPrefStr(@"lastResult") ?: @"还没有结果";
        [self toast:res];
    });
}

- (void)applyNow {
    notify_post(KZ_NOTIFY);
    [self refreshRows];
    [self toast:@"已发送应用指令…"];
    [self toastResultLater];
}

@end
