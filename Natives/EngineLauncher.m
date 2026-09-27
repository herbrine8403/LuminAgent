#import "EngineLauncher.h"
#import "Core/AirCore.h"
#import "UI/LASessionListVC.h"
#import "UI/LAChatVC.h"
#import "UI/LATutorialVC.h"
#import "Session/LASessionManager.h"
#import "Session/LASession.h"
#import "Session/LAMessage.h"
#import "Session/LAMessagePart.h"

/* 首次启动教程已读标记 */
static NSString *const kLATutorialShownKey = @"LuminAgentTutorialShown";

/* 引擎启动器实现：单例协调器，持有会话管理器与导航栈，
 * 实现列表/聊天双代理，打通 新建→会话→发送→落库 全链路。 */
@interface EngineLauncher () <LASessionListDelegate, LAChatDelegate>
@property (nonatomic, strong) LASessionManager *manager;
@property (nonatomic, weak) UINavigationController *nav;
@property (nonatomic, weak) LASessionListVC *list;
@end

@implementation EngineLauncher

// 获取全局单例（线程安全）。
+ (instancetype)sharedLauncher {
    static EngineLauncher *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EngineLauncher alloc] init];
    });
    return shared;
}

// 启动流程：初始化注册表与会话管理器 → 装配列表 → 首启弹教程。
- (UIViewController *)launchWithWindow:(UIWindow *)window {
    (void)window;
    NSLog(@"[LuminAgent] 引擎启动 Core 版本: %s", AirCoreVersion());
    // 初始化插件注册表（占位实现，后续加载 JSON 清单）
    AirPluginRegistryInit();

    // 会话管理器：内存库起步（磁盘持久化由存储层后续接入）
    _manager = [[LASessionManager alloc] initWithStore:nil];

    // 根界面：会话列表（含 Bento 引导卡），协调器任其代理
    LASessionListVC *root = [[LASessionListVC alloc] init];
    root.delegate = self;
    _list = root;
    [self reloadSessionList];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    _nav = nav;

    // 首启教程：待窗口可见后模态展示一次
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kLATutorialShownKey]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentTutorialIfNeeded];
        });
    }
    return nav;
}

/* 列表数据重载（新建/删除/恢复后统一入口，失败走空引导卡） */
- (void)reloadSessionList {
    NSError *error = nil;
    NSArray *sessions = [_manager rootSessionsWithError:&error];
    if (!sessions) {
        [_list showErrorWithRetryTarget:self action:@selector(reloadSessionList)];
        return;
    }
    [_list reloadWithSessions:sessions];
}

#pragma mark - LASessionListDelegate

/* 右上角 + / 引导卡：建 Build 会话 → 刷新列表 → 推入聊天 */
- (void)sessionListDidTapCreate:(LASessionListVC *)list {
    (void)list;
    NSError *error = nil;
    LASession *s = [_manager createSessionWithTitle:NSLocalizedString(@"session.new", nil)
                                          parentID:nil
                                              mode:LAAgentMainModeBuild
                                      firstMessage:nil
                                             error:&error];
    if (!s) {
        NSLog(@"[LuminAgent] 创建会话失败: %@", error);
        return;
    }
    [self reloadSessionList];
    [self pushChatForSession:s messages:@[]];
}

/* 点选会话：取消息后推入聊天 */
- (void)sessionList:(LASessionListVC *)list didSelectSession:(LASession *)session {
    (void)list;
    if (!session) {
        return;
    }
    NSError *error = nil;
    NSArray<LAMessage *> *msgs = [_manager messagesForSessionID:session.sessionID error:&error];
    [self pushChatForSession:session messages:msgs ?: @[]];
}

- (void)pushChatForSession:(LASession *)session messages:(NSArray<LAMessage *> *)messages {
    LAChatVC *chat = [[LAChatVC alloc] init];
    chat.sessionID = session.sessionID;
    chat.delegate = self;
    chat.title = session.title.length > 0 ? session.title : NSLocalizedString(@"session.title", nil);
    [chat reloadWithMessages:messages];
    [_nav pushViewController:chat animated:YES];
}

#pragma mark - LAChatDelegate

/* 发送：用户消息落库 → 本地助手回执落库 → 刷新（模型直连后续接入 Provider 网关） */
- (void)chatVC:(LAChatVC *)vc didSendText:(NSString *)text {
    if (!vc.sessionID || text.length == 0) {
        return;
    }
    NSError *error = nil;
    LAMessage *userMsg = [LAMessage messageWithSessionID:vc.sessionID role:LAMessageRoleUser];
    [userMsg appendPart:[LAMessagePart partWithKind:LAMessagePartKindText text:text]];
    if (![_manager appendMessage:userMsg tokensIn:0 tokensOut:0 costMicro:0 error:&error]) {
        NSLog(@"[LuminAgent] 用户消息落库失败: %@", error);
        return;
    }
    LAMessage *ack = [LAMessage messageWithSessionID:vc.sessionID role:LAMessageRoleAssistant];
    [ack appendPart:[LAMessagePart partWithKind:LAMessagePartKindText
                                          text:NSLocalizedString(@"chat.local.ack", nil)]];
    [_manager appendMessage:ack tokensIn:0 tokensOut:0 costMicro:0 error:NULL];
    NSArray<LAMessage *> *msgs = [_manager messagesForSessionID:vc.sessionID error:NULL];
    [vc reloadWithMessages:msgs ?: @[]];
}

#pragma mark - Tutorial

- (void)presentTutorialIfNeeded {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLATutorialShownKey]) {
        return;
    }
    LATutorialVC *t = [[LATutorialVC alloc] init];
    __weak typeof(self) weakSelf = self;
    t.completion = ^{
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kLATutorialShownKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [weakSelf.nav dismissViewControllerAnimated:YES completion:nil];
    };
    t.modalPresentationStyle = UIModalPresentationFullScreen;
    [_nav presentViewController:t animated:YES completion:nil];
}

@end
