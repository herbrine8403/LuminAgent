#ifndef LA_LSP_DIAGNOSER_H
#define LA_LSP_DIAGNOSER_H

#import <Foundation/Foundation.h>

// LSP 只读诊断错误域。
extern NSString * const LALSPErrorDomain;

// 诊断级别：error / warning（行内展示用）。
typedef NS_ENUM(NSInteger, LADiagnosticSeverity) {
    LADiagnosticSeverityError   = 1,
    LADiagnosticSeverityWarning = 2,
};

// 符号种类（ObjC/C 轻量符号表）。
typedef NS_ENUM(NSInteger, LASymbolKind) {
    LASymbolKindObjCInterface      = 1, // @interface X
    LASymbolKindObjCImplementation = 2, // @implementation X
    LASymbolKindObjCProtocol       = 3, // @protocol X
    LASymbolKindObjCMethod         = 4, // -/+ (…)name
    LASymbolKindCFunction          = 5, // ret name(…) {
    LASymbolKindImport             = 6, // #import/#include
    LASymbolKindDefine             = 7, // #define X
};

// 轻量符号：名 + 种类 + 文件 + 行号。
@interface LASymbol : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) LASymbolKind kind;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) NSInteger line; // 1 起
@end

// 行内诊断模型：文件 + 行列 + 级别 + 信息 + 规则名。
@interface LADiagnostic : NSObject
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) NSInteger line;   // 1 起
@property (nonatomic, assign) NSInteger column; // 1 起
@property (nonatomic, assign) LADiagnosticSeverity severity;
@property (nonatomic, copy) NSString *message;  // 中文信息
@property (nonatomic, copy) NSString *rule;     // 规则名，如 bracket-balance
@end

// LSP 只读诊断器：内置 ObjC/C 正则符号表 + 轻诊断，不常驻 server；
// 每次调用即时计算，编辑后由调用方触发 refreshAfterEditAtPath: 刷新（目标 2s 内更新 UI）。
@interface LALSPDiagnoser : NSObject

// 单文件符号表（只读，不落盘）。
- (NSArray<LASymbol *> *)symbolsInFileAtPath:(NSString *)path error:(NSError **)error;

// 单文件诊断（error/warning 行内模型）。
- (NSArray<LADiagnostic *> *)diagnoseFileAtPath:(NSString *)path error:(NSError **)error;

// 编辑后刷新：重跑 diagnose（无缓存 server，可直接调用 diagnose；本接口显式表达语义并回传耗时）。
- (nullable NSArray<LADiagnostic *> *)refreshAfterEditAtPath:(NSString *)path
                                            elapsedMilliseconds:(NSTimeInterval * _Nullable)elapsedMs
                                                          error:(NSError **)error;

@end

#endif /* LA_LSP_DIAGNOSER_H */
