#include <llvm-c/Core.h>
#include <llvm-c/Error.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/LLJIT.h>
#include <llvm-c/Target.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void check(LLVMErrorRef error) {
    if (error) {
        char *message = LLVMGetErrorMessage(error);
        fprintf(stderr, "%s\n", message);
        LLVMDisposeErrorMessage(message);
        exit(1);
    }
}

int main(int argc, char **argv) {
    if (argc != 2 || LLVMInitializeNativeTarget() || LLVMInitializeNativeAsmPrinter()) {
        return 1;
    }
    LLVMOrcLLJITRef jit;
    check(LLVMOrcCreateLLJIT(&jit, NULL));
    LLVMContextRef context = LLVMContextCreate();
    LLVMMemoryBufferRef buffer;
    LLVMModuleRef module;
    char *message = NULL;
    if (LLVMCreateMemoryBufferWithContentsOfFile(argv[1], &buffer, &message)
        || LLVMParseIRInContext(context, buffer, &module, &message)) {
        fprintf(stderr, "%s\n", message);
        LLVMDisposeMessage(message);
        return 1;
    }
    LLVMSetTarget(module, LLVMOrcLLJITGetTripleString(jit));
    LLVMSetDataLayout(module, LLVMOrcLLJITGetDataLayoutStr(jit));
    LLVMOrcThreadSafeContextRef safe_context = LLVMOrcCreateNewThreadSafeContextFromLLVMContext(context);
    LLVMOrcThreadSafeModuleRef safe_module = LLVMOrcCreateNewThreadSafeModule(module, safe_context);
    LLVMOrcDisposeThreadSafeContext(safe_context);
    check(LLVMOrcLLJITAddLLVMIRModule(jit, LLVMOrcLLJITGetMainJITDylib(jit), safe_module));
    LLVMOrcExecutorAddress address;
    check(LLVMOrcLLJITLookup(jit, &address, "answer"));
    int (*answer)(int) = (int (*)(int))(uintptr_t)address;
    if (answer(35) != 42) {
        return 1;
    }
    check(LLVMOrcDisposeLLJIT(jit));
    puts("Static C SDK consumer and native ORC JIT passed");
    return 0;
}
