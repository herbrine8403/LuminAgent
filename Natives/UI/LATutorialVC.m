#import "LATutorialVC.h"
#import "DesignSystem/AirSurface.h"
#import "DesignSystem/AirOutline.h"

@interface LATutorialVC () <UIScrollViewDelegate>
@end

@implementation LATutorialVC {
    UIScrollView *_pager;
    UIPageControl *_dots;
    NSArray<NSDictionary *> *_pages;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [AirSurface backgroundColor];

    _pages = @[
        @{@"icon": @"bubble.left.and.bubble.right.fill",
          @"title": NSLocalizedString(@"tutorial.p1.title", nil),
          @"desc": NSLocalizedString(@"tutorial.p1.desc", nil)},
        @{@"icon": @"cpu.fill",
          @"title": NSLocalizedString(@"tutorial.p2.title", nil),
          @"desc": NSLocalizedString(@"tutorial.p2.desc", nil)},
        @{@"icon": @"command.square.fill",
          @"title": NSLocalizedString(@"tutorial.p3.title", nil),
          @"desc": NSLocalizedString(@"tutorial.p3.desc", nil)},
        @{@"icon": @"lock.shield.fill",
          @"title": NSLocalizedString(@"tutorial.p4.title", nil),
          @"desc": NSLocalizedString(@"tutorial.p4.desc", nil)},
    ];

    UILabel *head = [[UILabel alloc] init];
    head.text = NSLocalizedString(@"tutorial.title", nil);
    head.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    head.textColor = [UIColor labelColor];
    head.textAlignment = NSTextAlignmentCenter;
    head.translatesAutoresizingMaskIntoConstraints = NO;
    head.accessibilityLabel = head.text;
    [self.view addSubview:head];

    _pager = [[UIScrollView alloc] init];
    _pager.pagingEnabled = YES;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.delegate = self;
    _pager.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_pager];

    UIView *strip = [[UIView alloc] init];
    strip.translatesAutoresizingMaskIntoConstraints = NO;
    [_pager addSubview:strip];

    UIView *prev = nil;
    for (NSDictionary *p in _pages) {
        UIView *card = [self pageCardWithIcon:p[@"icon"]
                                        title:p[@"title"]
                                         desc:p[@"desc"]];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        [strip addSubview:card];
        [NSLayoutConstraint activateConstraints:@[
            [card.topAnchor constraintEqualToAnchor:strip.topAnchor constant:AirSpaceXL],
            [card.bottomAnchor constraintEqualToAnchor:strip.bottomAnchor constant:-AirSpaceXL],
            [card.widthAnchor constraintEqualToAnchor:_pager.widthAnchor constant:-48],
            [card.heightAnchor constraintEqualToAnchor:_pager.heightAnchor constant:-32],
        ]];
        if (prev) {
            [card.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:16].active = YES;
        } else {
            [card.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor constant:24].active = YES;
        }
        prev = card;
    }
    [prev.trailingAnchor constraintEqualToAnchor:strip.trailingAnchor constant:-24].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [strip.topAnchor constraintEqualToAnchor:_pager.topAnchor],
        [strip.bottomAnchor constraintEqualToAnchor:_pager.bottomAnchor],
        [strip.leadingAnchor constraintEqualToAnchor:_pager.leadingAnchor],
        [strip.trailingAnchor constraintEqualToAnchor:_pager.trailingAnchor],
        [strip.heightAnchor constraintEqualToAnchor:_pager.heightAnchor],
    ]];

    _dots = [[UIPageControl alloc] init];
    _dots.numberOfPages = _pages.count;
    _dots.currentPage = 0;
    _dots.pageIndicatorTintColor = [UIColor tertiaryLabelColor];
    _dots.currentPageIndicatorTintColor = LAAcentColor();
    _dots.translatesAutoresizingMaskIntoConstraints = NO;
    [_dots addTarget:self action:@selector(didChangeDot:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_dots];

    UIButton *skip = [UIButton buttonWithType:UIButtonTypeSystem];
    [skip setTitle:NSLocalizedString(@"tutorial.skip", nil) forState:UIControlStateNormal];
    skip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [skip setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    skip.translatesAutoresizingMaskIntoConstraints = NO;
    [skip addTarget:self action:@selector(didTapClose) forControlEvents:UIControlEventTouchUpInside];
    skip.accessibilityLabel = skip.currentTitle;
    [self.view addSubview:skip];

    UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
    [start setTitle:NSLocalizedString(@"tutorial.start", nil) forState:UIControlStateNormal];
    start.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [start setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    start.backgroundColor = LAAcentColor();
    start.layer.cornerRadius = AirRadiusMD;
    start.layer.cornerCurve = kCACornerCurveContinuous;
    start.translatesAutoresizingMaskIntoConstraints = NO;
    [start addTarget:self action:@selector(didTapClose) forControlEvents:UIControlEventTouchUpInside];
    start.accessibilityLabel = start.currentTitle;
    [self.view addSubview:start];

    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:AirSpaceXL],
        [head.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AirSpaceXL],
        [head.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AirSpaceXL],
        [_pager.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:AirSpaceLG],
        [_pager.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_pager.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_pager.bottomAnchor constraintEqualToAnchor:_dots.topAnchor constant:-AirSpaceLG],
        [_dots.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_dots.bottomAnchor constraintEqualToAnchor:skip.topAnchor constant:-AirSpaceLG],
        [skip.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AirSpaceXL],
        [skip.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-AirSpaceLG],
        [skip.heightAnchor constraintEqualToConstant:44],
        [start.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AirSpaceXL],
        [start.bottomAnchor constraintEqualToAnchor:skip.bottomAnchor],
        [start.heightAnchor constraintEqualToConstant:44],
        [start.widthAnchor constraintEqualToConstant:160],
    ]];
}

- (UIView *)pageCardWithIcon:(NSString *)icon title:(NSString *)title desc:(NSString *)desc {
    UIView *card = [[UIView alloc] init];
    [AirSurface applyCardStyleToView:card level:AirSurfaceLevelHigh];

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iv.tintColor = LAAcentColor();
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:iv];

    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    t.textColor = [UIColor labelColor];
    t.textAlignment = NSTextAlignmentCenter;
    t.numberOfLines = 0;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:t];

    UILabel *d = [[UILabel alloc] init];
    d.text = desc;
    d.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    d.textColor = [UIColor secondaryLabelColor];
    d.textAlignment = NSTextAlignmentCenter;
    d.numberOfLines = 0;
    d.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:d];

    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:card.topAnchor constant:32],
        [iv.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iv.widthAnchor constraintEqualToConstant:64],
        [iv.heightAnchor constraintEqualToConstant:64],
        [t.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:AirSpaceXL],
        [t.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:AirSpaceXL],
        [t.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-AirSpaceXL],
        [d.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:AirSpaceLG],
        [d.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:AirSpaceXL],
        [d.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-AirSpaceXL],
    ]];
    card.isAccessibilityElement = YES;
    card.accessibilityLabel = [NSString stringWithFormat:@"%@。%@", title, desc];
    return card;
}

- (void)didChangeDot:(UIPageControl *)dots {
    CGFloat x = dots.currentPage * _pager.bounds.size.width;
    [_pager setContentOffset:CGPointMake(x, 0) animated:YES];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    NSInteger page = (NSInteger)llround(sv.contentOffset.x / MAX(1, sv.bounds.size.width));
    page = MAX(0, MIN(page, (NSInteger)_pages.count - 1));
    _dots.currentPage = page;
}

- (void)didTapClose {
    if (self.completion) { self.completion(); }
}

@end
