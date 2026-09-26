#import "VMTileBaseCell.h"
#import "DesignSystem/AirSurface.h"
#import "DesignSystem/AirOutline.h"
#import "DesignSystem/AirAnimation.h"

/* 磁贴基类实现：卡片风 + 按压弹簧 + 选中三层 */

@implementation VMTileBaseCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        /* 卡片风：L2 容器 + 中阴影 + 12 圆角 continuous */
        self.contentView.backgroundColor = [AirSurface containerColorForLevel:AirSurfaceLevelDefault];
        self.contentView.layer.cornerRadius = AirRadiusMD;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderWidth = 0.5;
        self.contentView.layer.borderColor = [AirOutline variantColor].CGColor;
        self.contentView.layer.masksToBounds = YES;
        [AirShadow applyMediumShadowToView:self cornerRadius:AirRadiusMD];

        _iconContainer = [[UIView alloc] init];
        _iconContainer.backgroundColor = [AirSurface itemColor];
        _iconContainer.layer.cornerRadius = 10;
        _iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
        _iconContainer.layer.masksToBounds = YES;
        _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconContainer addSubview:_iconView];
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:22],
            [_iconView.heightAnchor constraintEqualToConstant:22],
        ]];

        /* 标题 title3 15pt Semibold + 缩放 0.7~0.8 防截断 */
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.7;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        /* 副标题 caption1 11pt Regular */
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        /* chevron：tertiary 可点暗示 */
        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevronView.tintColor = [UIColor tertiaryLabelColor];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;

        /* 选中徽章：accent 圆点 + 白色对勾，默认隐藏 */
        _selectedBadge = [[UIView alloc] init];
        _selectedBadge.backgroundColor = LAAcentColor();
        _selectedBadge.layer.cornerRadius = 9;
        _selectedBadge.layer.masksToBounds = YES;
        _selectedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
        check.tintColor = [UIColor whiteColor];
        check.translatesAutoresizingMaskIntoConstraints = NO;
        [_selectedBadge addSubview:check];
        [NSLayoutConstraint activateConstraints:@[
            [check.centerXAnchor constraintEqualToAnchor:_selectedBadge.centerXAnchor],
            [check.centerYAnchor constraintEqualToAnchor:_selectedBadge.centerYAnchor],
            [check.widthAnchor constraintEqualToConstant:10],
            [check.heightAnchor constraintEqualToConstant:10],
        ]];
        _selectedBadge.hidden = YES;

        [self.contentView addSubview:_iconContainer];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_subtitleLabel];
        [self.contentView addSubview:_chevronView];
        [self.contentView addSubview:_selectedBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_iconContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AirSpaceXL],
            [_iconContainer.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconContainer.widthAnchor constraintEqualToConstant:40],
            [_iconContainer.heightAnchor constraintEqualToConstant:40],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconContainer.trailingAnchor constant:AirSpaceLG],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AirSpaceXL],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-AirSpaceLG],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:AirSpaceXS],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AirSpaceXL],
            [_chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:12],
            [_chevronView.heightAnchor constraintEqualToConstant:16],
            [_selectedBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AirSpaceLG],
            [_selectedBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AirSpaceLG],
            [_selectedBadge.widthAnchor constraintEqualToConstant:18],
            [_selectedBadge.heightAnchor constraintEqualToConstant:18],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

/* 选中三层：1.5pt accent 边框 + 徽章 + 背景轻染色 */
- (void)setSelectedState:(BOOL)selected {
    if (selected) {
        self.contentView.layer.borderColor = LAAcentColor().CGColor;
        self.contentView.layer.borderWidth = 1.5;
        self.selectedBadge.hidden = NO;
        self.contentView.backgroundColor =
            [LAAcentColor() colorWithAlphaComponent:0.08];
    } else {
        self.contentView.layer.borderColor = [AirOutline variantColor].CGColor;
        self.contentView.layer.borderWidth = 0.5;
        self.selectedBadge.hidden = YES;
        self.contentView.backgroundColor =
            [AirSurface containerColorForLevel:AirSurfaceLevelDefault];
    }
}

- (void)setDisabled:(BOOL)disabled {
    self.alpha = disabled ? AirDisabledAlpha : 1.0;
    self.userInteractionEnabled = !disabled;
}

- (void)setTappable:(BOOL)tappable {
    self.chevronView.hidden = !tappable;
}

- (void)setCompactAdaptive:(BOOL)compact {
    self.titleLabel.adjustsFontForContentSizeCategory = !compact;
    self.subtitleLabel.adjustsFontForContentSizeCategory = !compact;
}

/* 按压弹簧（阻尼 0.7，初速 0.8，压至 0.96） */
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [AirAnimation pressDownView:self];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [AirAnimation releaseView:self];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [AirAnimation releaseView:self];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.transform = CGAffineTransformIdentity;
    [self setSelectedState:NO];
    [self setDisabled:NO];
}

@end
