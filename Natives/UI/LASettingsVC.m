#import "LASettingsVC.h"
#import "DesignSystem/AirSurface.h"
#import "DesignSystem/AirOutline.h"
#import "DesignSystem/AirAnimation.h"

/* 设置行：标题 + 副标题 + 右侧附件（chevron/switch/segmented 三选一） */
typedef NS_ENUM(NSInteger, LACardRowAccessory) {
    LACardRowAccessoryChevron = 0,
    LACardRowAccessorySwitch = 1,
    LACardRowAccessorySegmented = 2,
    LACardRowAccessoryNone = 3,
};

@interface LACardRowView : UIView
- (void)configureWithTitle:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                 accessory:(LACardRowAccessory)kind;
/* 附件控件（调用方挂值/事件）：switch 或 segmented */
@property (nonatomic, strong, readonly, nullable) UISwitch *rowSwitch;
@property (nonatomic, strong, readonly, nullable) UISegmentedControl *rowSegment;
@end

@implementation LACardRowView {
    UILabel *_titleLabel;
    UILabel *_subLabel;
    UIImageView *_chevron;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [AirSurface containerColorForLevel:AirSurfaceLevelDefault];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.8;
        _subLabel = [[UILabel alloc] init];
        _subLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _subLabel.textColor = [UIColor secondaryLabelColor];
        _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevron.tintColor = [UIColor tertiaryLabelColor];
        for (UIView *v in @[_titleLabel, _subLabel, _chevron]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AirSpaceXL],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:AirSpaceLG],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_chevron.leadingAnchor constant:-AirSpaceLG],
            [_subLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-AirSpaceLG],
            [_chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceXL],
            [_chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chevron.widthAnchor constraintEqualToConstant:12],
            [_chevron.heightAnchor constraintEqualToConstant:16],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

/* 附件装配：chevron 显示 / switch 右置 / segmented 右置 */
- (void)configureWithTitle:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                 accessory:(LACardRowAccessory)kind {
    _titleLabel.text = title;
    _subLabel.text = subtitle;
    _subLabel.hidden = (subtitle.length == 0);
    _chevron.hidden = (kind != LACardRowAccessoryChevron);
    [_rowSwitch removeFromSuperview];
    _rowSwitch = nil;
    [_rowSegment removeFromSuperview];
    _rowSegment = nil;
    if (kind == LACardRowAccessorySwitch) {
        _rowSwitch = [[UISwitch alloc] init];
        _rowSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_rowSwitch];
        [NSLayoutConstraint activateConstraints:@[
            [_rowSwitch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceXL],
            [_rowSwitch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        self.accessibilityTraits = UIAccessibilityTraitNone;
    } else if (kind == LACardRowAccessorySegmented) {
        _rowSegment = [[UISegmentedControl alloc] initWithItems:@[@"跟随", @"快", @"慢"]];
        _rowSegment.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_rowSegment];
        [NSLayoutConstraint activateConstraints:@[
            [_rowSegment.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceXL],
            [_rowSegment.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_rowSegment.widthAnchor constraintEqualToConstant:150],
        ]];
        self.accessibilityTraits = UIAccessibilityTraitNone;
    }
    self.accessibilityLabel = subtitle.length > 0
        ? [NSString stringWithFormat:@"%@，%@", title, subtitle] : title;
}

@end

@implementation LASettingsVC {
    UIScrollView *_scroll;
    UIStackView *_page;
}

/* 分组标题（Section header：标题 + 副标题，labelColor 系） */
- (UILabel *)groupHeaderWithTitle:(NSString *)title subtitle:(NSString *)sub {
    UILabel *h = [[UILabel alloc] init];
    h.text = title;
    h.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    h.textColor = [UIColor labelColor];
    h.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", title, sub];
    return h;
}

/* 分组栈：垂直 spacing 2（space-bento），行按 CardPosition 套遮罩 */
- (UIStackView *)groupStackWithRows:(NSArray<LACardRowView *> *)rows {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = AirSpaceBento; /* 2pt 拼接 */
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSUInteger i = 0; i < rows.count; i++) {
        AirCardPosition pos;
        if (rows.count == 1) {
            pos = AirCardPositionSingle;
        } else if (i == 0) {
            pos = AirCardPositionTop;
        } else if (i == rows.count - 1) {
            pos = AirCardPositionBottom;
        } else {
            pos = AirCardPositionMiddle;
        }
        LACardRowView *row = rows[i];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;
        /* 遮罩圆角：layout 后按 bounds 生成 */
        [row layoutIfNeeded];
        [self applyPosition:pos toRow:row];
    }
    return stack;
}

/* 按 bounds 套 CardPosition 遮罩（外 28 / 内 4） */
- (void)applyPosition:(AirCardPosition)pos toRow:(LACardRowView *)row {
    CGSize size = CGSizeMake(MAX(320, row.bounds.size.width), MAX(56, row.bounds.size.height));
    UIBezierPath *path = [AirSurface cornerPathForPosition:pos
                                                    bounds:CGRectMake(0, 0, size.width, size.height)];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = path.CGPath;
    /* 遮罩按行宽自适应：frame 在 layout 后修正 */
    mask.frame = CGRectMake(0, 0, size.width, size.height);
    row.layer.mask = mask;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"settings.title", nil);
    self.view.backgroundColor = [AirSurface backgroundColor];

    _scroll = [[UIScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll];
    _page = [[UIStackView alloc] init];
    _page.axis = UILayoutConstraintAxisVertical;
    _page.spacing = AirSpaceXL;
    _page.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_page];

    CGFloat side = self.view.bounds.size.width >= 600 ? AirSpaceXL : AirSpaceLG;
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_page.topAnchor constraintEqualToAnchor:_scroll.topAnchor constant:AirSpaceLG],
        [_page.bottomAnchor constraintEqualToAnchor:_scroll.bottomAnchor constant:-AirSpaceLG],
        [_page.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:side],
        [_page.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-side],
    ]];

    /* 分组一：外观（动效分段 + 背景透明度开关） */
    [_page addArrangedSubview:[self groupHeaderWithTitle:NSLocalizedString(@"settings.appearance", nil)
                                               subtitle:@"动效/背景"]];
    LACardRowView *animRow = [[LACardRowView alloc] init];
    [animRow configureWithTitle:NSLocalizedString(@"settings.animation", nil)
                       subtitle:NSLocalizedString(@"settings.animation.desc", nil)
                      accessory:LACardRowAccessorySegmented];
    animRow.rowSegment.selectedSegmentIndex = 0;
    [animRow.rowSegment addTarget:self action:@selector(animSpeedChanged:)
                 forControlEvents:UIControlEventValueChanged];
    LACardRowView *bgRow = [[LACardRowView alloc] init];
    [bgRow configureWithTitle:NSLocalizedString(@"settings.wallpaper.dim", nil)
                     subtitle:nil accessory:LACardRowAccessorySwitch];
    [_page addArrangedSubview:[self groupStackWithRows:@[animRow, bgRow]]];

    /* 分组二：模型（寻址 chevron + 超时说明） */
    [_page addArrangedSubview:[self groupHeaderWithTitle:NSLocalizedString(@"settings.model", nil)
                                               subtitle:@"provider/model"]];
    LACardRowView *modelRow = [[LACardRowView alloc] init];
    [modelRow configureWithTitle:NSLocalizedString(@"settings.model.id", nil)
                        subtitle:@"zen/zen-default"
                       accessory:LACardRowAccessoryChevron];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(modelRowTapped)];
    [modelRow addGestureRecognizer:tap];
    [_page addArrangedSubview:[self groupStackWithRows:@[modelRow]]];

    /* 分组三：MCP（服务器 chevron + 授权说明） */
    [_page addArrangedSubview:[self groupHeaderWithTitle:NSLocalizedString(@"settings.mcp", nil)
                                               subtitle:@"MCP"]];
    LACardRowView *mcpRow = [[LACardRowView alloc] init];
    [mcpRow configureWithTitle:NSLocalizedString(@"settings.mcp.servers", nil)
                      subtitle:NSLocalizedString(@"settings.mcp.desc", nil)
                     accessory:LACardRowAccessoryChevron];
    [_page addArrangedSubview:[self groupStackWithRows:@[mcpRow]]];

    /* 分组四：关于（版本行，无附件） */
    [_page addArrangedSubview:[self groupHeaderWithTitle:NSLocalizedString(@"settings.about", nil)
                                               subtitle:@"LuminAgent"]];
    LACardRowView *verRow = [[LACardRowView alloc] init];
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    [verRow configureWithTitle:NSLocalizedString(@"settings.version", nil)
                      subtitle:ver accessory:LACardRowAccessoryNone];
    [_page addArrangedSubview:[self groupStackWithRows:@[verRow]]];
}

/* 动效偏好落盘：0=跟随默认，其余映射 general.transition_animation_type */
- (void)animSpeedChanged:(UISegmentedControl *)seg {
    NSInteger mapped = seg.selectedSegmentIndex == 0 ? 1 : (seg.selectedSegmentIndex == 1 ? 3 : 2);
    [[NSUserDefaults standardUserDefaults] setInteger:mapped forKey:@"general.transition_animation_type"];
}

/* 模型行：预留跳转（后续接 Provider 配置页） */
- (void)modelRowTapped {
    NSLog(@"[LuminAgent] 模型行点击，待接 Provider 配置页");
}

/* 遮罩随宽度重算（横竖屏/分屏） */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for (UIStackView *group in _page.arrangedSubviews) {
        if (![group isKindOfClass:[UIStackView class]]) {
            continue;
        }
        NSArray *rows = group.arrangedSubviews;
        for (NSUInteger i = 0; i < rows.count; i++) {
            if (![rows[i] isKindOfClass:[LACardRowView class]]) {
                continue;
            }
            LACardRowView *row = rows[i];
            AirCardPosition pos = AirCardPositionSingle;
            if (rows.count > 1) {
                pos = (i == 0) ? AirCardPositionTop
                    : (i == rows.count - 1 ? AirCardPositionBottom : AirCardPositionMiddle);
            }
            UIBezierPath *path = [AirSurface cornerPathForPosition:pos bounds:row.bounds];
            CAShapeLayer *mask = [CAShapeLayer layer];
            mask.path = path.CGPath;
            mask.frame = row.bounds;
            row.layer.mask = mask;
        }
    }
}

- (void)viewWillTransitionToSize:(CGSize)size
      withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    } completion:nil];
}

@end
