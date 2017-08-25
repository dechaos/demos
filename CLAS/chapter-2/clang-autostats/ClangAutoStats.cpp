//
//  Created by Gabriel Li on 2017/8/8.
//
//

#include "clang/AST/AST.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/ASTConsumer.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Driver/Options.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Sema/SemaConsumer.h"
#include "clang/Tooling/CommonOptionsParser.h"
#include "clang/Tooling/Tooling.h"

using namespace clang;
using namespace clang::driver;
using namespace clang::tooling;
using namespace llvm;

static cl::OptionCategory OptsCategory("ClangAutoStats");

class ClangAutoStatsVisitor : public RecursiveASTVisitor<ClangAutoStatsVisitor> {
public:
    explicit ClangAutoStatsVisitor(ASTContext *Ctx) {}
    
    bool VisitObjCImplementationDecl(ObjCImplementationDecl *ID) {
        for (auto D : ID->decls()) {
            if (ObjCMethodDecl *MD = dyn_cast<ObjCMethodDecl>(D)) {
                handleObjcMethDecl(MD);
            }
        }
        return true;
    }
    
    bool handleObjcMethDecl(ObjCMethodDecl *MD) {
        if (!MD->hasBody()) return true;
        errs() << MD->getNameAsString() << "\n";
        return true;
    }
};

class ClangAutoStatsASTConsumer : public ASTConsumer {
private:
    ClangAutoStatsVisitor Visitor;
public:
    explicit ClangAutoStatsASTConsumer(CompilerInstance *aCI)
    : Visitor(&(aCI->getASTContext())) {}
    
    virtual void HandleTranslationUnit(ASTContext &context) override {
        Visitor.TraverseTranslationUnitDecl(context.getTranslationUnitDecl());
    }
};

class ClangAutoStatsAction : public ASTFrontendAction {
public:
    virtual std::unique_ptr<ASTConsumer> CreateASTConsumer(CompilerInstance &CI, StringRef file) override {
        return llvm::make_unique<ClangAutoStatsASTConsumer>(&CI);
    }
};

#pragma mark 入口

int main(int argc, const char **argv) {
    CommonOptionsParser op(argc, argv, OptsCategory);
    ClangTool Tool(op.getCompilations(), op.getSourcePathList());
    int result = Tool.run(newFrontendActionFactory<ClangAutoStatsAction>().get());
    return result;
}
