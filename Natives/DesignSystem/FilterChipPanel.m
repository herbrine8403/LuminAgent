#import "FilterChipPanel.h"
#import "AirSurface.h"
#import "AirOutline.h"

/* chip 条实现：UIStackView 横排 + 单选染色 */

static const CGFloat kChipHeight = 28.0;
static const CGFloat kChipRadius = 14.0; /* = 高度 / 2 胶囊 */

@implementation FilterChipPanel {
    UIStackView *_stack;
    NSArray<NSString *> *_titles;
    NSMutableArray<UIButton *> *_chips;
    NSInteger _selectedIndex;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _selectedIndex = -1;
        _chips = [NSMutableArray array];
        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisHorizontal;
        _stack.spacing = AirSpaceMD; /* 6pt chip 间距 */
        _stack.alignment = UIStackViewAlignmentCenter;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
        ]];
        self.isAccessibilityElement = NO;
    }
    return self;
}

- (NSInteger)selectedIndex {
    return _selectedIndex;
}

/* 重建 chip：标题 + 12pt Medium + 高 28 + 圆角 14 */
- (void)setTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)index {
    _titles = [titles copy];
    for (UIButton *chip in _chips) {
        [chip removeFromSuperview];
    }
    [_chips removeAllObjects];
    for (NSUInteger i = 0; i < _titles.count; i++) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:_titles[i] forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        chip.titleLabel.adjustsFontSizeToFitWidth = YES;
        chip.titleLabel.minimumScaleFactor = 0.75;
        chip.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        chip.layer.cornerRadius = kChipRadius;
        chip.layer.cornerCurve = kCACornerCurveContinuous;
        chip.layer.masksToBounds = YES;
        chip.tag = (NSInteger)i;
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        [chip.heightAnchor constraintEqualToConstant:kChipHeight].active = YES;
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        chip.accessibilityLabel = _titles[i];
        chip.accessibilityTraits = UIAccessibilityTraitButton;
        [_stack addArrangedSubview:chip];
        [_chips addObject:chip];
    }
    [self selectIndex:index notify:NO];
}

/* 点击：单选切换 + 选中染色 + delegate */
- (void)chipTapped:(UIButton *)sender {
    [self selectIndex:sender.tag notify:YES];
}

- (void)selectIndex:(NSInteger)index notify:(BOOL)notify {
    if (index < -1 || index >= (NSInteger)_chips.count) {
        return;
    }
    _selectedIndex = index;
    for (NSUInteger i = 0; i < _chips.count; i++) {
        [self applyStyle:_chips[i] selected:((NSInteger)i == index)];
    }
    if (notify && [self.delegate respondsToSelector:@selector(chipPanel:didSelectIndex:)]) {
        [self.delegate chipPanel:self didSelectIndex:index];
    }
}

/* 选中：accent 底 + 白字（accent 底保证对比）；未选中：半透明底 + 主文字 + variant 描边 */
- (void)applyStyle:(UIButton *)chip selected:(BOOL)selected {
    if (selected) {
        chip.backgroundColor = LAAcentColor();
        [chip setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        chip.layer.borderWidth = 0;
        chip.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitSelected;
    } else {
        chip.backgroundColor = [AirSurface itemColor];
        [chip setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        chip.layer.borderWidth = 0.5;
        chip.layer.borderColor = [AirOutline variantColor].CGColor;
        chip.accessibilityTraits = UIAccessibilityTraitButton;
    }
}

@end
