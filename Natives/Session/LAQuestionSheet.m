#import "LAQuestionSheet.h"
#import "LAErrors.h"
#import <UIKit/UIKit.h>

/* 问卷实现：UIAlertController Action Sheet + 信号量阻塞 */

@implementation LAQuestionOption

+ (instancetype)optionWithID:(NSString *)optionID
                       title:(NSString *)title
                      detail:(NSString *)detail {
    LAQuestionOption *option = [[LAQuestionOption alloc] init];
    option.optionID = [optionID copy] ?: [[NSUUID UUID] UUIDString];
    option.title = [title copy] ?: @"";
    option.detail = [detail copy];
    return option;
}

@end

@implementation LAQuestion

+ (instancetype)questionWithTitle:(NSString *)title
                          message:(NSString *)message
                          options:(NSArray<LAQuestionOption *> *)options {
    LAQuestion *question = [[LAQuestion alloc] init];
    question.questionID = [[NSUUID UUID] UUIDString];
    question.title = [title copy] ?: @"";
    question.message = [message copy];
    question.options = [options copy] ?: @[];
    return question;
}

@end

@implementation LAQuestionSheet

- (void)presentQuestion:(LAQuestion *)question
     onViewController:(UIViewController *)viewController
           completion:(void (^)(LAQuestionOption *option, NSError *error))completion {
    /* 单测通道：直接取预置答案 */
    if (self.testAnswerProvider) {
        LAQuestionOption *answer = self.testAnswerProvider(question);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (answer) {
                    completion(answer, nil);
                } else {
                    completion(nil, LAErrorWithCode(LAErrorCodePermissionDenied,
                                                    @"问卷已取消"));
                }
            });
        }
        return;
    }
    if (!question || question.options.count == 0) {
        if (completion) {
            completion(nil, LAErrorWithCode(LAErrorCodeImportInvalid, @"问卷无选项"));
        }
        return;
    }
    if (!viewController) {
        if (completion) {
            completion(nil, LAErrorWithCode(LAErrorCodeNotFound, @"问卷缺少宿主视图"));
        }
        return;
    }
    /* UI 必须在主线程弹出 */
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *sheet = [UIAlertController
            alertControllerWithTitle:question.title
                             message:question.message
                      preferredStyle:UIAlertControllerStyleActionSheet];
        for (LAQuestionOption *option in question.options) {
            NSString *buttonTitle = option.detail.length > 0
                ? [NSString stringWithFormat:@"%@（%@）", option.title, option.detail]
                : option.title;
            UIAlertActionStyle style = option.destructive
                ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;
            [sheet addAction:[UIAlertAction actionWithTitle:buttonTitle
                                                      style:style
                                                    handler:^(__unused UIAlertAction *action) {
                if (completion) {
                    completion(option, nil);
                }
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(__unused UIAlertAction *action) {
            if (completion) {
                completion(nil, LAErrorWithCode(LAErrorCodePermissionDenied,
                                                @"问卷已取消"));
            }
        }]];
        /* iPad 弹窗锚点：无来源时居中 */
        UIPopoverPresentationController *popover = sheet.popoverPresentationController;
        if (popover) {
            popover.sourceView = viewController.view;
            popover.sourceRect = CGRectMake(CGRectGetMidX(viewController.view.bounds),
                                            CGRectGetMidY(viewController.view.bounds),
                                            1, 1);
            popover.permittedArrowDirections = 0;
        }
        [viewController presentViewController:sheet animated:YES completion:nil];
    });
}

- (LAQuestionOption *)presentQuestionBlocking:(LAQuestion *)question
                           onViewController:(UIViewController *)viewController
                                      error:(NSError **)error {
    /* 主线程禁止阻塞等待，防止死锁 */
    if ([NSThread isMainThread]) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeStoreFailure,
                                     @"阻塞式问卷禁止在主线程调用");
        }
        return nil;
    }
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block LAQuestionOption *result = nil;
    __block NSError *waitError = nil;
    [self presentQuestion:question onViewController:viewController
               completion:^(LAQuestionOption *option, NSError *optionError) {
        result = option;
        waitError = optionError;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (error && !result) {
        *error = waitError ?: LAErrorWithCode(LAErrorCodePermissionDenied, @"问卷已取消");
    }
    return result;
}

@end
