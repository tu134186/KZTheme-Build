#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define KZ_DOMAIN @"com.minis.kztheme"
#define KZ_NOTIFY "com.minis.kztheme.changed"

// 私有但稳定的接口，显式声明避免编译报未声明
@interface PSSpecifier (KZPrivate)
- (id)performGetter;
- (void)performSetterWithValue:(id)value;
@end

@interface PSListController (KZPrivate)
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

@interface PSSpecifier (KZCellClass)
- (void)setCellClass:(Class)cls;
- (Class)cellClass;
@end

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

// 任何改动都自动触发 SpringBoard 里的插件重新应用（去抖 0.7s）
static void KZScheduleApply(void) {
    static int64_t kLast = 0;
    int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    if (now - kLast < 700) return;
    kLast = now;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post(KZ_NOTIFY);
    });
}

#pragma mark - 带加减按钮的滑块

@interface KZStepperCell : PSTableCell
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@end

@implementation KZStepperCell {
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

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:17];
        _nameLabel.text = [specifier propertyForKey:@"label"];
        [self.contentView addSubview:_nameLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_valueLabel];

        _slider = [[UISlider alloc] init];
        _slider.minimumValue = (float)_min;
        _slider.maximumValue = (float)_max;
        [_slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_slider];

        _minus = [self makeStepButton:@"\u2212"];
        [_minus addTarget:self action:@selector(stepDown:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_minus];

        _plus = [self makeStepButton:@"+"];
        [_plus addTarget:self action:@selector(stepUp:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_plus];

        [self refreshCellContentsWithSpecifier:specifier];
    }
    return self;
}

- (UIButton *)makeStepButton:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    b.backgroundColor = [UIColor secondarySystemBackgroundColor];
    b.layer.cornerRadius = 8;
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
    self.slider.value = (float)v;
    self.valueLabel.text = [NSString stringWithFormat:@"%.2f", v];
    KZScheduleApply();
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    double d = [self currentValue];
    self.slider.value = (float)d;
    self.valueLabel.text = [NSString stringWithFormat:@"%.2f", d];
    self.nameLabel.text = [specifier propertyForKey:@"label"];
}

- (void)sliderChanged:(UISlider *)s {
    double v = round(s.value / _step) * _step;
    [self writeValue:v];
}

- (void)stepDown:(UIButton *)b {
    [self writeValue:[self currentValue] - _step];
}

- (void)stepUp:(UIButton *)b {
    [self writeValue:[self currentValue] + _step];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.hidden = YES;
    self.detailTextLabel.hidden = YES;
    CGRect b = self.contentView.bounds;
    CGFloat w = b.size.width;
    CGFloat h = MAX(b.size.height, 76.0);
    self.nameLabel.frame = CGRectMake(16, 8, w - 140, 21);
    self.valueLabel.frame = CGRectMake(w - 118, 8, 102, 21);
    _minus.frame = CGRectMake(14, h - 40, 40, 30);
    _plus.frame = CGRectMake(w - 54, h - 40, 40, 30);
    self.slider.frame = CGRectMake(60, h - 40, w - 124, 30);
}

@end

#pragma mark - 根控制器

@interface KZRootListController : PSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation KZRootListController

- (id)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        Class stepper = NSClassFromString(@"KZStepperCell");
        for (PSSpecifier *s in _specifiers) {
            if ([s propertyForKey:@"action"]) [s setTarget:self];
            NSString *key = [s propertyForKey:@"key"];
            if ([key isEqualToString:@"scale"] || [key isEqualToString:@"duration"]) {
                if (stepper) {
                    [s setProperty:stepper forKey:@"cellClass"];
                    if ([s respondsToSelector:@selector(setCellClass:)]) [s setCellClass:stepper];
                }
                [s setProperty:@76 forKey:@"height"];
            }
        }
        [self refreshDynamicRows:NO];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        KZPrefSet(key, value);
        KZScheduleApply();
    }
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = key ? KZPrefStr(key) : nil;
    if (!v) v = [specifier propertyForKey:@"default"];
    return v;
}

#pragma mark 动态文字

- (NSString *)eyeTitle {
    NSString *eye = KZPrefStr(@"eye") ?: @"sharingan";
    NSString *shown = [eye isEqualToString:@"custom"] ? @"自定义图片" : eye;
    return [NSString stringWithFormat:@"当前素材：%@", shown];
}

- (NSString *)countdownTitle {
    NSString *cd = KZPrefStr(@"countdown") ?: @"B";
    NSDictionary *names = @{ @"A": @"A 六边形白点", @"B": @"B 彩色数字", @"C": @"C 彩色秒表" };
    return [NSString stringWithFormat:@"样式：%@（点一下换下一套）", names[cd] ?: cd];
}

- (NSString *)statusText {
    NSString *seen = KZPrefStr(@"lastSeen");
    if (!seen) return @"插件：未运行（tweak 没被注入，或刚重启不到 3 秒）";
    double d = [[NSDate date] timeIntervalSince1970] - [seen doubleValue];
    NSString *ago = d < 90 ? @"刚刚" : [NSString stringWithFormat:@"%.0f 分钟前", d / 60.0];
    return [NSString stringWithFormat:@"插件：运行中（%@）", ago];
}

- (void)refreshDynamicRows:(BOOL)reload {
    NSString *res = KZPrefStr(@"lastResult") ?: @"无记录";
    for (PSSpecifier *s in self.specifiers) {
        NSString *key = [s propertyForKey:@"key"];
        if ([key isEqualToString:@"eyeName"]) {
            [s setProperty:[self eyeTitle] forKey:@"label"];
        } else if ([key isEqualToString:@"countdown"]) {
            [s setProperty:[self countdownTitle] forKey:@"label"];
        } else if ([key isEqualToString:@"kzStatus"]) {
            [s setProperty:[self statusText] forKey:@"label"];
        } else if ([key isEqualToString:@"kzResult"]) {
            [s setProperty:[NSString stringWithFormat:@"上次应用：%@", res] forKey:@"label"];
        }
    }
    if (reload) [self.tableView reloadData];
}

- (void)notifyRow {
    [self refreshDynamicRows:YES];
}

- (void)refreshStatus {
    [self refreshDynamicRows:YES];
}

- (void)cycleCountdown {
    NSArray *vals = @[ @"A", @"B", @"C" ];
    NSString *cur = KZPrefStr(@"countdown") ?: @"B";
    NSUInteger i = [vals indexOfObject:cur];
    NSUInteger next = (i == NSNotFound) ? 1 : (i + 1) % vals.count;
    KZPrefSet(@"countdown", vals[next]);
    [self notifyRow];
    notify_post(KZ_NOTIFY);
}

- (void)storeImage:(UIImage *)img {
    if (!img) return;
    // 先规整方向
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
    CGRect crop = CGRectMake((double)(w - side) / 2.0, (double)(h - side) / 2.0, (double)side, (double)side);
    CGImageRef square = CGImageCreateWithImageInRect(cg, crop);
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
    [self notifyRow];
    notify_post(KZ_NOTIFY);
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已导入"
                                                              message:@"已经保存为当前素材，开始录屏即可看到。"
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

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    BOOL access = [u startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:u];
    if (access) [u stopAccessingSecurityScopedResource];
    if (data) [self storeImage:[UIImage imageWithData:data]];
}

- (void)resetEye {
    KZPrefSet(@"eye", @"sharingan");
    CFPreferencesSetAppValue(CFSTR("eyeImage"), NULL, (__bridge CFStringRef)KZ_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)KZ_DOMAIN);
    [self notifyRow];
    KZScheduleApply();
    [self reloadSpecifiers];
}

- (void)promptNumberForKey:(NSString *)key title:(NSString *)title min:(double)mn max:(double)mx {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:nil
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = KZPrefStr(key);
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        double v = [a.textFields.firstObject.text doubleValue];
        if (v < mn) v = mn;
        if (v > mx) v = mx;
        KZPrefSet(key, [NSString stringWithFormat:@"%.2f", v]);
        notify_post(KZ_NOTIFY);
        [weakSelf reloadSpecifiers];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editScale {
    [self promptNumberForKey:@"scale" title:@"大小（0.10 - 0.60）" min:0.1 max:0.6];
}

- (void)editDuration {
    [self promptNumberForKey:@"duration" title:@"转速秒数（0.2 - 5.0）" min:0.2 max:5.0];
}

- (void)applyNow {
    KZPrefSet(@"appliedAt", @([[NSDate date] timeIntervalSince1970]));
    notify_post(KZ_NOTIFY);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshStatus];
    });
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已应用"
                                                              message:@"设置已经写进挂载目录。现在开始录屏就能看到；如果没变化，去 Dopamine 注销一次。"
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshDynamicRows:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshDynamicRows:YES];
}

@end
