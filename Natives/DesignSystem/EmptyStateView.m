#import "EmptyStateView.h"
#import "AirSurface.h"
#import "AirOutline.h"
#import "ShimmerView.h"

/* 三态实现：同一容器复用，show 即清场重建 */

@implementation EmptyStateView {
    NSMutableArray<ShimmerView *> *_shimmers;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _shimmers = [NSMutableArray array];
        self.isAccessibilityElement = NO;
    }
    return self;
}

/* 清场：移除子视图并停止骨架动画 */
- (void)clear {
    for (ShimmerView *s in _shimmers) {
        [s stopShimmering];
    }
    [_shimmers removeAllObjects];
    for (UIView *v in self.subviews) {
        [v removeFromSuperview];
    }
}

/* 居中容器：纵向栈，间距 8 */
- (UIStackView *)centerStack {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = AirSpaceLG;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:AirSpace3XL],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-AirSpace3XL],
    ]];
    return stack;
}

/* 说明文字：Dynamic Type Body + 次级文字色 */
- (UILabel *)bodyLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

/* 主按钮：accent 底白字，胶囊圆角，焦点态预留 */
- (UIButton *)primaryButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.backgroundColor = LAAcentColor();
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = AirRadiusMD;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 20, 10, 20);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    if (target && action) {
        [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }
    button.accessibilityLabel = title;
    return button;
}

- (void)showEmptyWithIcon:(NSString *)symbolName
                    title:(NSString *)title
              actionTitle:(nullable NSString *)actionTitle
                   target:(nullable id)target
                   action:(nullable SEL)action {
    [self clear];
    self.accessibilityLabel = title;
    UIStackView *stack = [self centerStack];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName ?: @"tray"]];
    icon.tintColor = [UIColor tertiaryLabelColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:44].active = YES;
    [icon.heightAnchor constraintEqualToConstant:44].active = YES;
    [stack addArrangedSubview:icon];
    [stack addArrangedSubview:[self bodyLabelWithText:title]];
    if (actionTitle.length > 0) {
        [stack addArrangedSubview:[self primaryButtonWithTitle:actionTitle target:target action:action]];
    }
    self.hidden = NO;
}

- (void)showLoadingWithTitle:(nullable NSString *)title {
    [self clear];
    self.accessibilityLabel = title.length > 0 ? title : @"正在加载";
    UIStackView *stack = [self centerStack];
    if (title.length > 0) {
        [stack addArrangedSubview:[self bodyLabelWithText:title]];
    }
    /* 三行骨架：宽 220/180/200，高 14，圆角 4（L7） */
    NSArray<NSNumber *> *widths = @[@220, @180, @200];
    for (NSNumber *w in widths) {
        ShimmerView *bar = [[ShimmerView alloc] initWithCornerRadius:AirRadiusXS];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        [bar.widthAnchor constraintEqualToConstant:w.doubleValue].active = YES;
        [bar.heightAnchor constraintEqualToConstant:14].active = YES;
        [stack addArrangedSubview:bar];
        [_shimmers addObject:bar];
        [bar startShimmering];
    }
    self.hidden = NO;
}

- (void)showErrorWithTitle:(NSString *)title
               retryTitle:(NSString *)retryTitle
                   target:(nullable id)target
                   action:(nullable SEL)action {
    [self clear];
    self.accessibilityLabel = title;
    UIStackView *stack = [self centerStack];
    /* InlineMessage 风格：item 底 + continuous 12 + variant 描边 + 图标横排 */
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [AirSurface itemColor];
    card.layer.cornerRadius = AirRadiusMD;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [AirOutline variantColor].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card.widthAnchor constraintEqualToConstant:280].active = YES;
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
    icon.tintColor = [UIColor systemOrangeColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:22].active = YES;
    [icon.heightAnchor constraintEqualToConstant:22].active = YES;
    UILabel *label = [self bodyLabelWithText:title];
    label.textAlignment = NSTextAlignmentLeft;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = AirSpaceLG;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:AirSpaceXL],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-AirSpaceXL],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:AirSpaceXL],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-AirSpaceXL],
    ]];
    [stack addArrangedSubview:card];
    [stack addArrangedSubview:[self primaryButtonWithTitle:retryTitle target:target action:action]];
    self.hidden = NO;
}

- (void)dismiss {
    [self clear];
    self.hidden = YES;
}

@end
