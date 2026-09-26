#import "LATrajectoryVC.h"
#import "DesignSystem/AirSurface.h"
#import "DesignSystem/AirOutline.h"
#import "DesignSystem/AirAnimation.h"
#import "DesignSystem/FilterChipPanel.h"
#import "Harness/LATrajectoryStore.h"

/* 事件 Cell：类型图标容器 + 载荷摘要 + 来源插件 pill + caption1 时间 */
@interface LATrajectoryCell : UITableViewCell
- (void)configureWithEvent:(LATrajectoryEvent *)event;
@end

@implementation LATrajectoryCell {
    UIView *_iconBox;
    UIImageView *_icon;
    UILabel *_titleLabel;
    UILabel *_subLabel;
    UILabel *_pluginPill;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    self = [super initWithStyle:s reuseIdentifier:r];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [AirSurface containerColorForLevel:AirSurfaceLevelLow];
        card.layer.cornerRadius = AirRadiusSM;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderWidth = 0.5;
        card.layer.borderColor = [AirOutline variantColor].CGColor;
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.tag = 100;
        [self.contentView addSubview:card];
        _iconBox = [[UIView alloc] init];
        _iconBox.layer.cornerRadius = 8;
        _iconBox.layer.cornerCurve = kCACornerCurveContinuous;
        _iconBox.layer.masksToBounds = YES;
        _iconBox.translatesAutoresizingMaskIntoConstraints = NO;
        _icon = [[UIImageView alloc] init];
        _icon.tintColor = [UIColor whiteColor];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconBox addSubview:_icon];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.8;
        _subLabel = [[UILabel alloc] init];
        _subLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _subLabel.textColor = [UIColor tertiaryLabelColor];
        _subLabel.numberOfLines = 2;
        /* 来源插件 pill：强制彩色 box，禁止纯文本 */
        _pluginPill = [[UILabel alloc] init];
        _pluginPill.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        _pluginPill.textColor = [UIColor whiteColor];
        _pluginPill.textAlignment = NSTextAlignmentCenter;
        _pluginPill.layer.cornerRadius = 8;
        _pluginPill.layer.cornerCurve = kCACornerCurveContinuous;
        _pluginPill.layer.masksToBounds = YES;
        for (UIView *v in @[_iconBox, _titleLabel, _subLabel, _pluginPill]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [card addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AirSpaceSM],
            [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-AirSpaceSM],
            [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AirSpaceXL],
            [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AirSpaceXL],
            [_iconBox.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:AirSpaceLG],
            [_iconBox.topAnchor constraintEqualToAnchor:card.topAnchor constant:AirSpaceLG],
            [_iconBox.widthAnchor constraintEqualToConstant:26],
            [_iconBox.heightAnchor constraintEqualToConstant:26],
            [_icon.centerXAnchor constraintEqualToAnchor:_iconBox.centerXAnchor],
            [_icon.centerYAnchor constraintEqualToAnchor:_iconBox.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:14],
            [_icon.heightAnchor constraintEqualToConstant:14],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBox.trailingAnchor constant:AirSpaceLG],
            [_titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:AirSpaceLG],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_pluginPill.leadingAnchor constant:-AirSpaceLG],
            [_pluginPill.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_pluginPill.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-AirSpaceLG],
            [_pluginPill.heightAnchor constraintEqualToConstant:16],
            [_pluginPill.widthAnchor constraintGreaterThanOrEqualToConstant:52],
            [_subLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:AirSpaceXS],
            [_subLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-AirSpaceLG],
            [_subLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-AirSpaceLG],
        ]];
        self.isAccessibilityElement = YES;
    }
    return self;
}

/* 类型→图标/色：消息蓝、工具橙、起止绿、重试红、扩展紫 */
- (void)configureWithEvent:(LATrajectoryEvent *)event {
    NSString *kind = [LATrajectoryEvent stringFromType:event.type];
    _titleLabel.text = [NSString stringWithFormat:@"#%llu %@", (unsigned long long)event.seq, kind];
    id desc = event.payload[@"text"] ?: event.payload[@"summary"] ?: event.payload[@"extKind"] ?: @"—";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.timeStyle = NSDateFormatterMediumStyle;
    _subLabel.text = [NSString stringWithFormat:@"%@ · %@", [desc description],
        [fmt stringFromDate:event.timestamp]];
    NSString *symbol = @"circle";
    UIColor *color = [UIColor systemGrayColor];
    switch (event.type) {
        case LATrajectoryEventUserMessage:
        case LATrajectoryEventAssistantMsg:
            symbol = @"message.fill"; color = [UIColor systemBlueColor]; break;
        case LATrajectoryEventToolCall:
        case LATrajectoryEventToolResult:
            symbol = @"wrench.fill"; color = [UIColor systemOrangeColor]; break;
        case LATrajectoryEventTurnStart:
        case LATrajectoryEventTurnEnd:
        case LATrajectoryEventStepStart:
        case LATrajectoryEventStepEnd:
            symbol = @"flag.fill"; color = [UIColor systemGreenColor]; break;
        case LATrajectoryEventAttempt:
            symbol = @"arrow.counterclockwise"; color = [UIColor systemRedColor]; break;
        case LATrajectoryEventPluginExt:
            symbol = @"puzzlepiece.fill"; color = [UIColor systemPurpleColor]; break;
        default:
            symbol = @"doc.text.fill"; color = [UIColor systemTealColor]; break;
    }
    _icon.image = [UIImage systemImageNamed:symbol];
    _iconBox.backgroundColor = color;
    _pluginPill.text = [NSString stringWithFormat:@" %@ ", event.sourcePlugin];
    _pluginPill.backgroundColor = [UIColor systemTealColor];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，来源 %@",
        _titleLabel.text, event.sourcePlugin];
}

@end

@implementation LATrajectoryVC {
    LATrajectoryStore *_store;
    UITableView *_table;
    FilterChipPanel *_filter;
    NSArray<LATrajectoryEvent *> *_events;
    NSInteger _typeFilter; /* -1=全部 7=工具 4/5=消息 else=系统 */
}

- (instancetype)initWithStore:(LATrajectoryStore *)store {
    self = [super init];
    if (self) {
        _store = store;
        _typeFilter = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"trajectory.title", nil);
    self.view.backgroundColor = [AirSurface backgroundColor];

    _filter = [[FilterChipPanel alloc] init];
    _filter.delegate = (id<FilterChipPanelDelegate>)self;
    _filter.translatesAutoresizingMaskIntoConstraints = NO;
    _filter.accessibilityLabel = NSLocalizedString(@"trajectory.filter", nil);
    [self.view addSubview:_filter];
    [_filter setTitles:@[NSLocalizedString(@"trajectory.filter.all", nil),
                         NSLocalizedString(@"trajectory.filter.tool", nil),
                         NSLocalizedString(@"trajectory.filter.message", nil),
                         NSLocalizedString(@"trajectory.filter.system", nil)]
        selectedIndex:0];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 76;
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    [_table registerClass:[LATrajectoryCell class] forCellReuseIdentifier:@"Traj"];
    [self.view addSubview:_table];

    CGFloat side = self.view.bounds.size.width >= 600 ? AirSpaceXL : AirSpaceLG;
    [NSLayoutConstraint activateConstraints:@[
        [_filter.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:AirSpaceLG],
        [_filter.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:side],
        [_filter.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-side],
        [_filter.heightAnchor constraintEqualToConstant:28],
        [_table.topAnchor constraintEqualToAnchor:_filter.bottomAnchor constant:AirSpaceLG],
        [_table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [self reload];
}

- (void)reload {
    NSArray<LATrajectoryEvent *> *all = [_store eventsSinceSeq:0];
    if (_typeFilter == 0) {
        NSPredicate *p = [NSPredicate predicateWithFormat:
            @"type == %d OR type == %d",
            LATrajectoryEventToolCall, LATrajectoryEventToolResult];
        _events = [all filteredArrayUsingPredicate:p];
    } else if (_typeFilter == 1) {
        NSPredicate *p = [NSPredicate predicateWithFormat:
            @"type == %d OR type == %d",
            LATrajectoryEventUserMessage, LATrajectoryEventAssistantMsg];
        _events = [all filteredArrayUsingPredicate:p];
    } else if (_typeFilter == 2) {
        NSPredicate *p = [NSPredicate predicateWithFormat:
            @"type != %d AND type != %d AND type != %d AND type != %d",
            LATrajectoryEventToolCall, LATrajectoryEventToolResult,
            LATrajectoryEventUserMessage, LATrajectoryEventAssistantMsg];
        _events = [all filteredArrayUsingPredicate:p];
    } else {
        _events = all;
    }
    [_table reloadData];
}

- (void)chipPanel:(FilterChipPanel *)panel didSelectIndex:(NSInteger)index {
    _typeFilter = index - 1;
    [self reload];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    (void)s;
    return _events.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    LATrajectoryCell *cell = [tv dequeueReusableCellWithIdentifier:@"Traj" forIndexPath:ip];
    [cell configureWithEvent:_events[(NSUInteger)ip.row]];
    return cell;
}

- (void)viewWillTransitionToSize:(CGSize)size
      withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [self->_table reloadData];
    } completion:nil];
}

@end
