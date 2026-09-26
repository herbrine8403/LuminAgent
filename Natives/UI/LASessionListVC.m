#import "LASessionListVC.h"
#import "VMTileBaseCell.h"
#import "DesignSystem/AirSurface.h"
#import "DesignSystem/AirOutline.h"
#import "DesignSystem/AirAnimation.h"
#import "DesignSystem/FilterChipPanel.h"
#import "DesignSystem/EmptyStateView.h"
#import "Session/LASession.h"

/* 会话磁贴：标题 + 模式/时间副标题 + 模式色图标容器 */
@interface LASessionTileCell : VMTileBaseCell
- (void)configureWithSession:(LASession *)session featured:(BOOL)featured;
@end

@implementation LASessionTileCell

- (void)configureWithSession:(LASession *)session featured:(BOOL)featured {
    self.titleLabel.text = session.title.length > 0 ? session.title : @"未命名会话";
    BOOL isPlan = (session.mainMode == LAAgentMainModePlan);
    NSString *modeText = isPlan ? @"Plan 规划" : @"Build 构建";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:session.updatedAt];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@ · %@", modeText, [fmt stringFromDate:date]];
    self.iconContainer.backgroundColor = isPlan ? [UIColor systemPurpleColor] : [UIColor systemBlueColor];
    self.iconView.image = [UIImage systemImageNamed:isPlan ? @"map.fill" : @"hammer.fill"];
    self.iconView.tintColor = [UIColor whiteColor];
    [self setTappable:YES];
    [self setCompactAdaptive:!featured];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", self.titleLabel.text, modeText];
}

@end

/* 引导大磁贴：空会话引导卡（图标 + 文案 + 新建按钮位） */
@interface LAGuideTileCell : VMTileBaseCell
@end

@implementation LAGuideTileCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.titleLabel.text = NSLocalizedString(@"session.guide.title", nil);
        self.subtitleLabel.text = NSLocalizedString(@"session.guide.subtitle", nil);
        self.iconContainer.backgroundColor = LAAcentColor();
        self.iconView.image = [UIImage systemImageNamed:@"plus.bubble.fill"];
        self.iconView.tintColor = [UIColor whiteColor];
        [self setTappable:YES];
        self.accessibilityLabel = NSLocalizedString(@"session.guide.title", nil);
    }
    return self;
}

@end

@implementation LASessionListVC {
    UICollectionView *_collection;
    FilterChipPanel *_filterPanel;
    EmptyStateView *_emptyView;
    NSArray<LASession *> *_allSessions;
    NSArray<LASession *> *_visibleSessions;
    NSInteger _modeFilter; /* -1=全部 0=Build 1=Plan */
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"session.title", nil);
    self.view.backgroundColor = [AirSurface backgroundColor];
    _modeFilter = -1;

    /* 导航栏新建按钮（主操作显式入口） */
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self action:@selector(didTapCreate)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel =
        NSLocalizedString(@"session.create", nil);

    /* 筛选条：全部 / Build / Plan */
    _filterPanel = [[FilterChipPanel alloc] init];
    _filterPanel.delegate = (id<FilterChipPanelDelegate>)self;
    _filterPanel.translatesAutoresizingMaskIntoConstraints = NO;
    _filterPanel.accessibilityLabel = NSLocalizedString(@"session.filter", nil);
    [self.view addSubview:_filterPanel];
    [_filterPanel setTitles:@[NSLocalizedString(@"session.filter.all", nil),
                              NSLocalizedString(@"session.filter.build", nil),
                              NSLocalizedString(@"session.filter.plan", nil)]
             selectedIndex:0];

    /* Bento CompositionalLayout（禁用 FlowLayout 做主页） */
    UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:
            ^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
        return [self layoutSectionFor:section environment:env];
    }];
    _collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collection.backgroundColor = [UIColor clearColor];
    _collection.dataSource = self;
    _collection.delegate = self;
    _collection.translatesAutoresizingMaskIntoConstraints = NO;
    [_collection registerClass:[LAGuideTileCell class] forCellWithReuseIdentifier:@"Guide"];
    [_collection registerClass:[LASessionTileCell class] forCellWithReuseIdentifier:@"Session"];
    [self.view addSubview:_collection];

    _emptyView = [[EmptyStateView alloc] init];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self.view addSubview:_emptyView];

    CGFloat side = [self sideMargin];
    [NSLayoutConstraint activateConstraints:@[
        [_filterPanel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:AirSpaceLG],
        [_filterPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:side],
        [_filterPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-side],
        [_filterPanel.heightAnchor constraintEqualToConstant:28],
        [_collection.topAnchor constraintEqualToAnchor:_filterPanel.bottomAnchor constant:AirSpaceLG],
        [_collection.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_collection.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collection.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_emptyView.topAnchor constraintEqualToAnchor:_filterPanel.bottomAnchor],
        [_emptyView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

/* Pad/Phone 两套宽度：宽屏 12pt，窄屏 8pt */
- (CGFloat)sideMargin {
    return self.view.bounds.size.width >= 600 ? AirSpaceXL : AirSpaceLG;
}

/* 分区布局：0=引导大磁贴（全宽 140），1=会话（首个全宽 120 + 其余双列 96） */
- (NSCollectionLayoutSection *)layoutSectionFor:(NSInteger)section
                                   environment:(id<NSCollectionLayoutEnvironment>)env {
    CGFloat width = env.container.contentSize.width;
    BOOL wide = width >= 600; /* Pad/横屏/分屏宽 */
    CGFloat side = wide ? AirSpaceXL : AirSpaceLG;
    NSDirectionalEdgeInsets inset = NSDirectionalEdgeInsetsMake(AirSpaceLG, side, AirSpaceLG, side);
    if (section == 0) {
        NSCollectionLayoutSize *size = [NSCollectionLayoutSize sizeWithWidthDimension:
            [NSCollectionLayoutDimension fractionalWidthDimension:1.0]
            heightDimension:[NSCollectionLayoutDimension absoluteDimension:140]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:size
                                                                                    subitems:@[item]];
        NSCollectionLayoutSection *s = [NSCollectionLayoutSection sectionWithGroup:group];
        s.contentInsets = inset;
        return s;
    }
    /* 会话区：大磁贴（全宽 120）+ 小磁贴（双列 96）混排 */
    NSCollectionLayoutSize *bigSize = [NSCollectionLayoutSize sizeWithWidthDimension:
        [NSCollectionLayoutDimension fractionalWidthDimension:1.0]
        heightDimension:[NSCollectionLayoutDimension absoluteDimension:120]];
    NSCollectionLayoutItem *big = [NSCollectionLayoutItem itemWithLayoutSize:bigSize];
    NSCollectionLayoutGroup *bigGroup = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:bigSize
                                                                                   subitems:@[big]];
    CGFloat colCount = wide ? 3 : 2;
    NSCollectionLayoutSize *smallSize = [NSCollectionLayoutSize sizeWithWidthDimension:
        [NSCollectionLayoutDimension fractionalWidthDimension:1.0 / colCount]
        heightDimension:[NSCollectionLayoutDimension absoluteDimension:96]];
    NSMutableArray *smalls = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)colCount; i++) {
        [smalls addObject:[NSCollectionLayoutItem itemWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:
                [NSCollectionLayoutDimension fractionalWidthDimension:1.0 / colCount]
                heightDimension:[NSCollectionLayoutDimension absoluteDimension:96]]]];
    }
    NSCollectionLayoutGroup *smallGroup = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:smallSize
                                                                                       subitems:smalls];
    smallGroup.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:AirSpaceXL];
    NSCollectionLayoutGroup *mixed = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:
        [NSCollectionLayoutSize sizeWithWidthDimension:
            [NSCollectionLayoutDimension fractionalWidthDimension:1.0]
            heightDimension:[NSCollectionLayoutDimension estimatedDimension:400]]
        subitems:@[bigGroup, smallGroup]];
    mixed.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:AirSpaceXL];
    NSCollectionLayoutSection *s = [NSCollectionLayoutSection sectionWithGroup:mixed];
    s.contentInsets = inset;
    return s;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv {
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    if (section == 0) {
        return _allSessions.count == 0 ? 1 : 0; /* 无会话时引导卡 */
    }
    return _visibleSessions.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv
                 cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        LAGuideTileCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"Guide" forIndexPath:indexPath];
        cell.titleLabel.text = NSLocalizedString(@"session.guide.title", nil);
        return cell;
    }
    LASessionTileCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"Session" forIndexPath:indexPath];
    [cell configureWithSession:_visibleSessions[(NSUInteger)indexPath.item]
                      featured:(indexPath.item == 0)];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        [self didTapCreate];
        return;
    }
    LASession *s = _visibleSessions[(NSUInteger)indexPath.item];
    if ([self.delegate respondsToSelector:@selector(sessionList:didSelectSession:)]) {
        [self.delegate sessionList:self didSelectSession:s];
    }
}

/* chip 过滤：全部/Build/Plan */
- (void)chipPanel:(FilterChipPanel *)panel didSelectIndex:(NSInteger)index {
    _modeFilter = index - 1; /* 0→-1 全部，1→0 Build，2→1 Plan */
    [self applyFilter];
}

- (void)applyFilter {
    if (_modeFilter < 0) {
        _visibleSessions = _allSessions;
    } else {
        NSPredicate *p = [NSPredicate predicateWithFormat:@"mainMode == %d", (int)_modeFilter];
        _visibleSessions = [_allSessions filteredArrayUsingPredicate:p];
    }
    [_collection reloadData];
    [self refreshEmpty];
}

/* 数据源刷新 + 连锁进场 */
- (void)reloadWithSessions:(NSArray<LASession *> *)sessions {
    _allSessions = [sessions copy] ?: @[];
    [self applyFilter];
    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    for (UICollectionViewCell *c in _collection.visibleCells) {
        [cells addObject:c];
    }
    [AirAnimation animateItemsInChain:cells];
}

- (void)showLoading {
    _collection.hidden = YES;
    [_emptyView showLoadingWithTitle:NSLocalizedString(@"state.loading", nil)];
}

- (void)showErrorWithRetryTarget:(id)target action:(SEL)action {
    _collection.hidden = YES;
    [_emptyView showErrorWithTitle:NSLocalizedString(@"error.load.sessions", nil)
                        retryTitle:NSLocalizedString(@"state.retry", nil)
                            target:target action:action];
}

/* 空引导：无会话时 EmptyView 叠加引导（磁贴区同时保留引导卡） */
- (void)refreshEmpty {
    BOOL empty = (_visibleSessions.count == 0 && _allSessions.count == 0);
    _collection.hidden = NO;
    if (empty) {
        [_emptyView dismiss];
    } else {
        [_emptyView dismiss];
    }
}

- (void)didTapCreate {
    if ([self.delegate respondsToSelector:@selector(sessionListDidTapCreate:)]) {
        [self.delegate sessionListDidTapCreate:self];
    }
}

/* 横竖屏/分屏：宽度变化即重算布局 */
- (void)viewWillTransitionToSize:(CGSize)size
      withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [self->_collection.collectionViewLayout invalidateLayout];
    } completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.traitCollection.horizontalSizeClass != previous.horizontalSizeClass) {
        [_collection.collectionViewLayout invalidateLayout];
    }
}

@end
