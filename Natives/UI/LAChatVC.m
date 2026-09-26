#import "LAChatVC.h"
#import "DesignSystem/AirSurface.h"
#import "DesignSystem/AirOutline.h"
#import "DesignSystem/AirAnimation.h"
#import "Session/LAMessage.h"
#import "Session/LAMessagePart.h"
#import "Tools/LAPermissionAsking.h" /* 统一裁决枚举唯一真源 */

/* 工具调用卡实现：item 底 + 工具名行 + 参数摘要 + 状态 pill */
@implementation ToolCallCardView {
    UILabel *_toolLabel;
    UILabel *_argsLabel;
    UILabel *_statusPill;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [AirSurface itemColor];
        self.layer.cornerRadius = AirRadiusSM;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [AirOutline variantColor].CGColor;
        _toolLabel = [[UILabel alloc] init];
        _toolLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _toolLabel.textColor = [UIColor labelColor];
        _argsLabel = [[UILabel alloc] init];
        _argsLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _argsLabel.textColor = [UIColor secondaryLabelColor];
        _argsLabel.numberOfLines = 2;
        _statusPill = [[UILabel alloc] init];
        _statusPill.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        _statusPill.textColor = [UIColor whiteColor];
        _statusPill.textAlignment = NSTextAlignmentCenter;
        _statusPill.layer.cornerRadius = 8;
        _statusPill.layer.cornerCurve = kCACornerCurveContinuous;
        _statusPill.layer.masksToBounds = YES;
        for (UIView *v in @[_toolLabel, _argsLabel, _statusPill]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_toolLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:AirSpaceLG],
            [_toolLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AirSpaceLG],
            [_toolLabel.trailingAnchor constraintEqualToAnchor:_statusPill.leadingAnchor constant:-AirSpaceLG],
            [_statusPill.centerYAnchor constraintEqualToAnchor:_toolLabel.centerYAnchor],
            [_statusPill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceLG],
            [_statusPill.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [_statusPill.heightAnchor constraintEqualToConstant:16],
            [_argsLabel.topAnchor constraintEqualToAnchor:_toolLabel.bottomAnchor constant:AirSpaceSM],
            [_argsLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AirSpaceLG],
            [_argsLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceLG],
            [_argsLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-AirSpaceLG],
        ]];
        self.isAccessibilityElement = YES;
    }
    return self;
}

- (void)configureWithTool:(NSString *)tool arguments:(nullable NSString *)args status:(NSString *)status {
    _toolLabel.text = tool;
    _argsLabel.text = args.length > 0 ? args : @"—";
    _statusPill.text = [NSString stringWithFormat:@" %@ ", status];
    _statusPill.backgroundColor = [UIColor systemOrangeColor];
    self.accessibilityLabel = [NSString stringWithFormat:@"工具 %@，状态 %@", tool, status];
}

@end

/* 权限确认卡实现：标题栏 + 目标/原因 + 允许/拒绝双按钮 */
@implementation PermissionCardView {
    void (^_completion)(NSInteger);
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [AirSurface applyCardStyleToView:self level:AirSurfaceLevelHigh];
        self.isAccessibilityElement = NO;
    }
    return self;
}

- (void)configureWithTool:(NSString *)tool
                   target:(nullable NSString *)target
                   reason:(nullable NSString *)reason
              completion:(void (^)(NSInteger decision))completion {
    _completion = [completion copy];
    for (UIView *v in self.subviews) {
        [v removeFromSuperview];
    }
    /* 标题栏：cardTitle 底 + 分隔线（卡片头/身分段） */
    UIView *titleBar = [[UIView alloc] init];
    titleBar.backgroundColor = [AirSurface cardTitleColor];
    titleBar.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *title = [[UILabel alloc] init];
    title.text = NSLocalizedString(@"permission.title", nil);
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [titleBar addSubview:title];
    UIView *divider = [[UIView alloc] init];
    divider.backgroundColor = [AirOutline variantColor];
    divider.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *detail = [[UILabel alloc] init];
    detail.text = [NSString stringWithFormat:@"%@\n%@\n%@", tool, target ?: @"—", reason ?: @""];
    detail.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;
    detail.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *allow = [UIButton buttonWithType:UIButtonTypeSystem];
    [allow setTitle:NSLocalizedString(@"permission.allow", nil) forState:UIControlStateNormal];
    allow.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    allow.backgroundColor = LAAcentColor();
    [allow setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    allow.layer.cornerRadius = AirRadiusSM;
    allow.layer.cornerCurve = kCACornerCurveContinuous;
    allow.translatesAutoresizingMaskIntoConstraints = NO;
    [allow addTarget:self action:@selector(didTapAllow) forControlEvents:UIControlEventTouchUpInside];
    allow.accessibilityLabel = NSLocalizedString(@"permission.allow", nil);

    UIButton *deny = [UIButton buttonWithType:UIButtonTypeSystem];
    [deny setTitle:NSLocalizedString(@"permission.deny", nil) forState:UIControlStateNormal];
    deny.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [deny setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    deny.layer.cornerRadius = AirRadiusSM;
    deny.layer.cornerCurve = kCACornerCurveContinuous;
    deny.layer.borderWidth = 0.5;
    deny.layer.borderColor = [AirOutline outlineColor].CGColor;
    deny.translatesAutoresizingMaskIntoConstraints = NO;
    [deny addTarget:self action:@selector(didTapDeny) forControlEvents:UIControlEventTouchUpInside];
    deny.accessibilityLabel = NSLocalizedString(@"permission.deny", nil);

    for (UIView *v in @[titleBar, divider, detail, allow, deny]) {
        [self addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [titleBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:titleBar.topAnchor constant:AirSpaceLG],
        [title.bottomAnchor constraintEqualToAnchor:titleBar.bottomAnchor constant:-AirSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:titleBar.leadingAnchor constant:AirSpaceXL],
        [title.trailingAnchor constraintEqualToAnchor:titleBar.trailingAnchor constant:-AirSpaceXL],
        [divider.topAnchor constraintEqualToAnchor:titleBar.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [divider.heightAnchor constraintEqualToConstant:0.5],
        [detail.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:AirSpaceLG],
        [detail.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AirSpaceXL],
        [detail.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceXL],
        [allow.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:AirSpaceXL],
        [allow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:AirSpaceXL],
        [allow.trailingAnchor constraintEqualToAnchor:self.centerXAnchor constant:-AirSpaceSM],
        [allow.heightAnchor constraintEqualToConstant:40],
        [allow.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-AirSpaceXL],
        [deny.topAnchor constraintEqualToAnchor:allow.topAnchor],
        [deny.leadingAnchor constraintEqualToAnchor:self.centerXAnchor constant:AirSpaceSM],
        [deny.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-AirSpaceXL],
        [deny.heightAnchor constraintEqualToConstant:40],
    ]];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@",
        NSLocalizedString(@"permission.title", nil), tool];
}

- (void)didTapAllow {
    if (_completion) { _completion(LAPermissionDecisionAllow); }
}

- (void)didTapDeny {
    if (_completion) { _completion(LAPermissionDecisionDeny); }
}

@end

/* 气泡 Cell：头像容器 26pt + 气泡 + caption1 时间戳 */
@interface LAChatTextCell : UITableViewCell
- (void)configureWithMessage:(LAMessage *)message;
@end

@implementation LAChatTextCell {
    UIView *_avatarBox;
    UIImageView *_avatarIcon;
    UIView *_bubble;
    UILabel *_bodyLabel;
    UILabel *_timeLabel;
    UIStackView *_row;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseID {
    self = [super initWithStyle:style reuseIdentifier:reuseID];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        /* 26pt 头像容器，13pt 圆角 continuous */
        _avatarBox = [[UIView alloc] init];
        _avatarBox.layer.cornerRadius = 13;
        _avatarBox.layer.masksToBounds = YES;
        _avatarBox.translatesAutoresizingMaskIntoConstraints = NO;
        [_avatarBox.widthAnchor constraintEqualToConstant:26].active = YES;
        [_avatarBox.heightAnchor constraintEqualToConstant:26].active = YES;
        _avatarIcon = [[UIImageView alloc] init];
        _avatarIcon.tintColor = [UIColor whiteColor];
        _avatarIcon.contentMode = UIViewContentModeScaleAspectFit;
        _avatarIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_avatarBox addSubview:_avatarIcon];
        [NSLayoutConstraint activateConstraints:@[
            [_avatarIcon.centerXAnchor constraintEqualToAnchor:_avatarBox.centerXAnchor],
            [_avatarIcon.centerYAnchor constraintEqualToAnchor:_avatarBox.centerYAnchor],
            [_avatarIcon.widthAnchor constraintEqualToConstant:14],
            [_avatarIcon.heightAnchor constraintEqualToConstant:14],
        ]];
        /* 气泡：L2 圆角 12 continuous */
        _bubble = [[UIView alloc] init];
        _bubble.layer.cornerRadius = AirRadiusMD;
        _bubble.layer.cornerCurve = kCACornerCurveContinuous;
        _bubble.layer.borderWidth = 0.5;
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        /* 正文：body 13pt Medium + 缩放 0.7~0.8 */
        _bodyLabel = [[UILabel alloc] init];
        _bodyLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.adjustsFontSizeToFitWidth = YES;
        _bodyLabel.minimumScaleFactor = 0.7;
        _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        /* 时间戳：caption1 11pt */
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _timeLabel.textColor = [UIColor tertiaryLabelColor];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_bubble addSubview:_bodyLabel];
        [_bubble addSubview:_timeLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_bodyLabel.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:AirSpaceLG],
            [_bodyLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:AirSpaceXL],
            [_bodyLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-AirSpaceXL],
            [_timeLabel.topAnchor constraintEqualToAnchor:_bodyLabel.bottomAnchor constant:AirSpaceSM],
            [_timeLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-AirSpaceXL],
            [_timeLabel.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-AirSpaceLG],
        ]];
        _row = [[UIStackView alloc] initWithArrangedSubviews:@[_avatarBox, _bubble]];
        _row.axis = UILayoutConstraintAxisHorizontal;
        _row.spacing = AirSpaceLG;
        _row.alignment = UIStackViewAlignmentTop;
        _row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_row];
        [NSLayoutConstraint activateConstraints:@[
            [_row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AirSpaceSM],
            [_row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-AirSpaceSM],
            [_row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AirSpaceXL],
            [_row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AirSpaceXL],
        ]];
        self.isAccessibilityElement = YES;
    }
    return self;
}

/* 用户气泡 L2 + accent 染色 / AI 气泡 Surface 色；文字全 labelColor 系 */
- (void)configureWithMessage:(LAMessage *)message {
    BOOL isUser = (message.role == LAMessageRoleUser);
    NSMutableString *text = [NSMutableString string];
    for (LAMessagePart *p in message.parts) {
        if (p.kind == LAMessagePartKindText && p.text.length > 0) {
            [text appendString:p.text];
        }
    }
    _bodyLabel.text = text.length > 0 ? text : @"—";
    _bodyLabel.textColor = [UIColor labelColor];
    if (isUser) {
        _bubble.backgroundColor = [LAAcentColor() colorWithAlphaComponent:0.12];
        _bubble.layer.borderColor = [[AirOutline variantColor] CGColor];
        _avatarBox.backgroundColor = LAAcentColor();
        _avatarIcon.image = [UIImage systemImageNamed:@"person.fill"];
    } else {
        _bubble.backgroundColor = [AirSurface containerColorForLevel:AirSurfaceLevelDefault];
        _bubble.layer.borderColor = [[AirOutline variantColor] CGColor];
        _avatarBox.backgroundColor = [UIColor systemPurpleColor];
        _avatarIcon.image = [UIImage systemImageNamed:@"sparkles"];
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:message.createdAt];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.timeStyle = NSDateFormatterShortStyle;
    _timeLabel.text = [fmt stringFromDate:date];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@：%@",
        isUser ? @"用户" : @"助手", _bodyLabel.text];
}

@end

@implementation LAChatVC {
    UITableView *_table;
    UIView *_inputBar;
    UITextField *_inputField;
    UIButton *_sendButton;
    NSArray<LAMessage *> *_messages;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [AirSurface backgroundColor];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 90;
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    [_table registerClass:[LAChatTextCell class] forCellReuseIdentifier:@"ChatText"];
    [self.view addSubview:_table];

    /* 输入栏：item 底 + 12 圆角 + 焦点 1→2pt 动画 */
    _inputBar = [[UIView alloc] init];
    _inputBar.backgroundColor = [AirSurface itemColor];
    _inputBar.layer.cornerRadius = AirRadiusMD;
    _inputBar.layer.cornerCurve = kCACornerCurveContinuous;
    _inputBar.layer.borderWidth = 1.0;
    _inputBar.layer.borderColor = [AirOutline outlineColor].CGColor;
    _inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_inputBar];

    _inputField = [[UITextField alloc] init];
    _inputField.placeholder = NSLocalizedString(@"chat.input.placeholder", nil);
    _inputField.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _inputField.textColor = [UIColor labelColor];
    _inputField.delegate = (id<UITextFieldDelegate>)self;
    _inputField.translatesAutoresizingMaskIntoConstraints = NO;
    _inputField.accessibilityLabel = NSLocalizedString(@"chat.input.placeholder", nil);
    [_inputBar addSubview:_inputField];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_sendButton setImage:[UIImage systemImageNamed:@"paperplane.fill"] forState:UIControlStateNormal];
    _sendButton.tintColor = LAAcentColor();
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_sendButton addTarget:self action:@selector(didTapSend) forControlEvents:UIControlEventTouchUpInside];
    _sendButton.accessibilityLabel = NSLocalizedString(@"chat.send", nil);
    [_inputBar addSubview:_sendButton];

    CGFloat side = self.view.bounds.size.width >= 600 ? AirSpaceXL : AirSpaceLG;
    [NSLayoutConstraint activateConstraints:@[
        [_table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:_inputBar.topAnchor constant:-AirSpaceLG],
        [_inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:side],
        [_inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-side],
        [_inputBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-AirSpaceLG],
        [_inputField.topAnchor constraintEqualToAnchor:_inputBar.topAnchor constant:AirSpaceLG],
        [_inputField.bottomAnchor constraintEqualToAnchor:_inputBar.bottomAnchor constant:-AirSpaceLG],
        [_inputField.leadingAnchor constraintEqualToAnchor:_inputBar.leadingAnchor constant:AirSpaceXL],
        [_inputField.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-AirSpaceLG],
        [_sendButton.centerYAnchor constraintEqualToAnchor:_inputBar.centerYAnchor],
        [_sendButton.trailingAnchor constraintEqualToAnchor:_inputBar.trailingAnchor constant:-AirSpaceXL],
        [_sendButton.widthAnchor constraintEqualToConstant:28],
        [_sendButton.heightAnchor constraintEqualToConstant:28],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputFocusChanged:)
                                                 name:UITextFieldTextDidBeginEditingNotification object:_inputField];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputBlurChanged:)
                                                 name:UITextFieldTextDidEndEditingNotification object:_inputField];
}

/* 焦点态：边框 1→2pt + accent 色动画 */
- (void)updateFocusState:(BOOL)focused {
    [UIView animateWithDuration:0.2 animations:^{
        self->_inputBar.layer.borderWidth = focused ? 2.0 : 1.0;
        self->_inputBar.layer.borderColor = focused
            ? LAAcentColor().CGColor
            : [AirOutline outlineColor].CGColor;
    }];
}

- (void)inputFocusChanged:(NSNotification *)note {
    (void)note;
    [self updateFocusState:YES];
}

- (void)inputBlurChanged:(NSNotification *)note {
    (void)note;
    [self updateFocusState:NO];
}

- (void)didTapSend {
    NSString *text = [_inputField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return;
    }
    _inputField.text = @"";
    [self updateFocusState:NO];
    if ([self.delegate respondsToSelector:@selector(chatVC:didSendText:)]) {
        [self.delegate chatVC:self didSendText:text];
    }
}

- (void)reloadWithMessages:(NSArray<LAMessage *> *)messages {
    _messages = [messages copy] ?: @[];
    [_table reloadData];
    if (_messages.count > 0) {
        NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)_messages.count - 1 inSection:0];
        [_table scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    (void)s;
    return _messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    LAChatTextCell *cell = [tv dequeueReusableCellWithIdentifier:@"ChatText" forIndexPath:ip];
    [cell configureWithMessage:_messages[(NSUInteger)ip.row]];
    return cell;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
