#ifndef LA_QUESTION_SHEET_H
#define LA_QUESTION_SHEET_H

/* 阻塞式问卷：执行中需用户决断时弹出 Action Sheet（iPhone/iPad 自适应），
 * Agent 循环在后台线程同步等待用户选择；无 UI 环境可用 testAnswerProvider。 */

#import <Foundation/Foundation.h>

/* UIKit 仅 .m 引用，头文件前向声明以降低耦合 */
@class UIViewController;
@class LAQuestion;
@class LAQuestionOption;

@interface LAQuestionOption : NSObject

@property (nonatomic, copy) NSString *optionID;   /* 选项标识 */
@property (nonatomic, copy) NSString *title;      /* 选项标题 */
@property (nonatomic, copy) NSString *detail;     /* 选项说明，可空 */
@property (nonatomic, assign) BOOL destructive;   /* 危险样式 */

+ (instancetype)optionWithID:(NSString *)optionID
                       title:(NSString *)title
                      detail:(NSString *)detail;

@end

@interface LAQuestion : NSObject

@property (nonatomic, copy) NSString *questionID;
@property (nonatomic, copy) NSString *title;      /* 标题 */
@property (nonatomic, copy) NSString *message;    /* 说明，可空 */
@property (nonatomic, strong) NSArray<LAQuestionOption *> *options; /* 至少 1 项 */
@property (nonatomic, assign) BOOL allowCustomInput; /* 是否允许自定义输入（暂以取消处理） */

+ (instancetype)questionWithTitle:(NSString *)title
                          message:(NSString *)message
                          options:(NSArray<LAQuestionOption *> *)options;

@end

@interface LAQuestionSheet : NSObject

/* 单测/无 UI 注入：非 nil 时直接返回该答案，不弹 UI */
@property (nonatomic, copy) LAQuestionOption * (^testAnswerProvider)(LAQuestion *question);

/* 异步弹出：completion 在主线程回调用；用户取消经 error 回传 */
- (void)presentQuestion:(LAQuestion *)question
     onViewController:(UIViewController *)viewController
           completion:(void (^)(LAQuestionOption *option, NSError *error))completion;

/* 阻塞式：后台线程同步等待用户选择；禁止在主线程调用 */
- (LAQuestionOption *)presentQuestionBlocking:(LAQuestion *)question
                           onViewController:(UIViewController *)viewController
                                      error:(NSError **)error;

@end

#endif /* LA_QUESTION_SHEET_H */
