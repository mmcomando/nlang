// ldmd2 -g -fsanitize=address src/lexer.d && ./lexer

import core.stdc.stdio;
import core.stdc.stdlib;
import std.string;

alias int8 = byte;
alias int32 = int;
alias int64 = long;

struct String
{
    int8* ptr;
    int64 size;

    this(string str)
    {
        ptr = cast(int8*) str.ptr;
        size = str.length;
    }

    string getString()
    {
        return (cast(char*) ptr)[0 .. size].idup;
    }
}

int32 same(String* strA, String* strB)
{
    if (strA.size != strB.size)
    {
        return 0;
    }
    auto i = 0;
    while (i < strA.size)
    {
        if (strA.ptr[i] != strB.ptr[i])
        {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

///////////////////////////// Tokenization

struct Tokens
{
    String* ptr;
    int64 size;
}

void loadFile(String* fileContent)
{
    int32 seek_end = SEEK_END;
    int32 seek_set = SEEK_SET;
    FILE* f = fopen("test.nlang", "rb");
    fseek(f, 0, seek_end);
    int64 fsize = ftell(f);
    fseek(f, 0, seek_set);
    int8* str = cast(int8*) calloc(1, fsize + 1);
    fread(str, 1, fsize, f);
    fclose(f);
    str[fsize] = 0;

    fileContent.ptr = str;
    fileContent.size = fsize;
}

void addToArr(Tokens* tokens, int8* ptr, int64 size)
{
    String* s = tokens.ptr + tokens.size;
    s.ptr = ptr;
    s.size = size;
    tokens.size = tokens.size + 1;
}

void printLastToken(Tokens* tokens)
{
    String* s = tokens.ptr + tokens.size - 1;
    printf("'%.*s'\n", s.size, s.ptr);
}

void printTokens(Tokens* tokens)
{
    int32 i = 0;
    while (i < tokens.size)
    {
        String* s = &tokens.ptr[i];
        printf("'%.*s'\n", s.size, s.ptr);
        i = i + 1;
    }
}

int8* readComment(int8* currentChar, int8 endChar)
{
    currentChar = currentChar + 1;
    while (*currentChar != endChar)
    {
        currentChar = currentChar + 1;
    }
    currentChar = currentChar + 1;
    return currentChar;
}

int8* readStr(int8* currentChar, int8 endChar)
{

    currentChar = currentChar + 1; // Skip '
    while (*currentChar != endChar)
    {
        int8 c = *currentChar;
        if (c == '\\')
        {
            currentChar = currentChar + 1;
        }
        currentChar = currentChar + 1;
    }
    currentChar = currentChar + 1;
    return currentChar;
}

void tokenize(Tokens* tokens, String* fileContent)
{

    tokens.ptr = cast(String*) calloc(1024, allocMAX); // 1024 elements

    int8* wordStart = fileContent.ptr;
    int8* currentChar = fileContent.ptr;
    while (*currentChar != 0)
    {
        int8 c = *currentChar;
        if (c == '\'' || c == '"' || c == '#')
        {
            int8 endChar = c;
            if (c == '#')
            {
                endChar = '\n'; // To the end of line
            }
            int8* end = readStr(currentChar, endChar);
            addToArr(tokens, currentChar, end - currentChar);
            if (c == '#')
            {
                tokens.size = tokens.size - 1;
            }
            wordStart = end;
            currentChar = end;
            continue;
        }

        if (c == ' ' || c == '\n' || c == '(' || c == ')' || c == '{' || c == '}' || c == '[' || c == ']' || c == '.' || c == '*' || c == ';' || c == ',')
        {
            if (wordStart != currentChar)
            {
                addToArr(tokens, wordStart, currentChar - wordStart);
            }
            if (c != ' ' && c != '\n')
            {
                addToArr(tokens, currentChar, 1);
            }
            wordStart = currentChar + 1;
        }

        currentChar = currentChar + 1;
    }

    addToArr(tokens, fileContent.ptr, 0);
}

///////////////////////////// AST

struct VarDef
{
    String* type;
    String* name;
    bool isPtr;
    Statement* stm;
}

struct StructDef
{
    String* name;
    VarDef* varDefs;
    int64 varDefsSize;
}

struct Module
{
    StructDef* structDefs;
    int64 structDefsSize;

    FuncDef* funcDefs;
    int64 funcDefsSize;
}

String* skipToMatching(String* currentToken, int8 start, int8 end)
{
    while (start != 0 && currentToken.ptr[0] != start)
    {
        currentToken = currentToken + 1;
    }
    if (currentToken.ptr[0] == end)
    {

        currentToken = expect(currentToken, end);
        return currentToken;
    }

    currentToken = currentToken + 1; // Skip start
    auto balance = 1;
    while (balance > 0)
    {
        if (currentToken.ptr[0] == start)
        {
            balance = balance + 1;
        }
        if (currentToken.ptr[0] == end)
        {
            balance = balance - 1;
        }
        currentToken = currentToken + 1;
    }

    return currentToken;
}

String* parseVarDeclaration(String* currentToken, VarDef* varDef)
{

    varDef.type = currentToken;
    varDef.isPtr = false;

    currentToken = currentToken + 1;
    if (currentToken.ptr[0] == '*')
    {
        varDef.isPtr = 1;
        currentToken = currentToken + 1;
    }
    varDef.name = currentToken;
    currentToken = currentToken + 1;

    if (currentToken.ptr[0] == '=')
    {
        currentToken = currentToken + 1;
        Statement* stm = cast(Statement*) calloc(Statement.sizeof, 1);
        currentToken = parseStatement(currentToken, stm);
    }

    return currentToken;
}

String* parseStruct(String* currentToken, StructDef* structDef)
{

    currentToken = currentToken + 1; // Skip struct
    structDef.name = currentToken;
    currentToken = currentToken + 1; // Skip name
    currentToken = currentToken + 1; // Skip {
    while (currentToken.ptr[0] != '}')
    {
        VarDef* s = structDef.varDefs + structDef.varDefsSize;
        currentToken = parseVarDeclaration(currentToken, s);
        currentToken = currentToken + 1; // Skip ;
        structDef.varDefsSize = structDef.varDefsSize + 1;
    }
    currentToken = currentToken + 1; // Skip name
    return currentToken;
}

struct FuncDef
{
    String* name;

    VarDef* parDefs;
    int64 parDefsSize;

    Statement* statements;
    int64 statementsSize;
}

enum StatementType
{
    t_none = 0,
    t_num = 1, // 1
    t_String = 2, // aaa
    t_group = 3, // Statement op Statement
    t_var = 4, //
    t_while = 5, //
    t_if = 6, //
    t_dereference = 7, //
    t_continue = 8, //
    t_return = 9, //
    t_assign = 10, //
    t_funcCall = 11,
}

string[] StatementTypeNames = ["none", "num", "String", "group", "var", "while", "if", "dereference", "t_continue", "t_return", "t_assign", " t_funcCall",];

struct GroupElement
{
    Statement stm;
    String* op;
}

struct Group
{
    GroupElement* elements;
    int64 elementsSize;
}

struct Statement
{
    void* ptr;
    int32 type;
}

struct FuncCall
{
    String* name;
    Group* group;
}

struct While
{
    FuncCall call;
    Statement* statements;
    int64 statementsSize;

}

String* parseFuncCall(String* currentToken, FuncCall* call)
{
    call.name = currentToken;
    currentToken++;
    currentToken = expect(currentToken, '(');

    if (currentToken.ptr[0] == ')')
    {
        currentToken = expect(currentToken, ')');
        return currentToken;
    }

    Group* ggIN = cast(Group*) calloc(Group.sizeof, 1);
    ggIN.elements = cast(GroupElement*) calloc(GroupElement.sizeof, allocMAX);
    call.group = ggIN;
    currentToken = parseGroup(currentToken, ggIN);
    currentToken = expect(currentToken, ')');
    return currentToken;

}

String* parseGroup(String* currentToken, Group* gg)
{
    while (currentToken.ptr[0] != ')' && currentToken.ptr[0] != ';')
    {
        // printf("??NN '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
        GroupElement* ggEE = gg.elements + gg.elementsSize;
        gg.elementsSize++;

        String* nextToken = currentToken + 1;
        if (nextToken.ptr[0] == '(')
        {
            FuncCall* call = cast(FuncCall*) calloc(FuncCall.sizeof, 1);
            currentToken = parseFuncCall(currentToken, call);

            ggEE.stm.type = StatementType.t_funcCall;
            ggEE.stm.ptr = call;
            // printf("??OP '%.*s'  %ld --\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
            //continue;
        }
        else
        {

            ggEE.stm.type = StatementType.t_String;
            ggEE.stm.ptr = currentToken;
            currentToken++;
        }

        if (currentToken.ptr[0] == ')' || currentToken.ptr[0] == ';')
        {
            break;
        }

        ggEE.op = currentToken;
        currentToken++;
    }

    return currentToken;
}

String* parseStatement(String* currentToken, Statement* statement)
{
    auto k_while = String("while");
    auto k_if = String("if");
    auto k_var = String("var");
    auto k_continue = String("continue");
    auto k_return = String("return");
    auto k_aa = String("&&");
    auto k_oo = String("||");

    if (same(currentToken, &k_while) || same(currentToken, &k_if))
    {
        While* wwW = cast(While*) calloc(While.sizeof, 1);
        wwW.statements = cast(Statement*) calloc(Statement.sizeof, allocMAX);
        statement.type = StatementType.t_while;
        statement.ptr = wwW;

        currentToken = parseFuncCall(currentToken, &wwW.call);
        currentToken = expect(currentToken, '{');

        int www = 0;
        while (currentToken.ptr[0] != '}')
        {
            Statement* s = wwW.statements + wwW.statementsSize;
            currentToken = parseStatement(currentToken, s);
            // currentToken = expect(currentToken, ';');
            wwW.statementsSize = wwW.statementsSize + 1;
            assert(www++ < 20);
        }

        currentToken = expect(currentToken, '}');
        return currentToken;
    }
    // if (same(currentToken, &k_if))
    // {
    //     statement.type = StatementType.t_if;
    //     printf("??I '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    //     currentToken = skipToMatching(currentToken, '{', '}');
    //     return currentToken;
    // }
    if (same(currentToken, &k_continue))
    {
        statement.type = StatementType.t_String;
        statement.ptr = currentToken;
        currentToken++;
        currentToken = expect(currentToken, ';');
        return currentToken;
    }
    // if (same(currentToken, &k_return))
    // {
    //     printf("??D '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    //     statement.type = StatementType.t_return;
    //     currentToken = skipToMatching(currentToken, 0, ';');
    //     printf("??DE '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    //     return currentToken;
    // }
    if (same(currentToken, &k_var) || same(currentToken, &k_return))
    {
        auto isVar = same(currentToken, &k_var);
        // printf("??V '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
        currentToken = currentToken + 1; //Skip var

        Group* gg = cast(Group*) calloc(Group.sizeof, 1);
        gg.elements = cast(GroupElement*) calloc(GroupElement.sizeof, allocMAX);
        statement.type = isVar ? StatementType.t_var : StatementType.t_return;
        statement.ptr = gg;
        currentToken = parseGroup(currentToken, gg);
        currentToken = skipToMatching(currentToken, 0, ';');
        return currentToken;
    }

    // Default var    
    Group* gg = cast(Group*) calloc(Group.sizeof, 1);
    gg.elements = cast(GroupElement*) calloc(GroupElement.sizeof, allocMAX);
    statement.type = StatementType.t_group;
    statement.ptr = gg;
    currentToken = parseGroup(currentToken, gg);
    currentToken = skipToMatching(currentToken, 0, ';'); // ----
    // printf("??AA '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    //  printf("??B '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr-startTT);

    return currentToken;
}

String* expect(String* currentToken, int8 c)
{
    assert(currentToken.ptr[0] == c);
    return currentToken + 1;
}

String* parseFunc(String* currentToken, FuncDef* funcDef)
{
    currentToken = currentToken + 1; // Skip func
    funcDef.name = currentToken;
    currentToken = currentToken + 1; // Skip name
    currentToken = expect(currentToken, '(');
    while (currentToken.ptr[0] != ')')
    {
        VarDef* s = funcDef.parDefs + funcDef.parDefsSize;
        currentToken = parseVarDeclaration(currentToken, s);
        if (currentToken.ptr[0] == ',')
        {
            currentToken = currentToken + 1; // Skip ,
        }
        funcDef.parDefsSize = funcDef.parDefsSize + 1;
    }
    currentToken = expect(currentToken, ')');
    currentToken = expect(currentToken, '{');
    // printf("??SSS '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    int www = 0;
    while (currentToken.ptr[0] != '}')
    {
        Statement* s = funcDef.statements + funcDef.statementsSize;
        currentToken = parseStatement(currentToken, s);
        // currentToken = expect(currentToken, ';');
        funcDef.statementsSize = funcDef.statementsSize + 1;
        assert(www++ < 20);
    }
    // currentToken = currentToken + 1; // Skip }
    // printf("func '%.*s'\n", currentToken.size, currentToken.ptr);
    // printf("??KKK '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    currentToken = skipToMatching(currentToken, 0, '}');
    // printf("??KKK2 '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
    return currentToken;
}

enum allocMAX = 128;
void makeModule(Module* modul, Tokens* tokens)
{
    auto k_func = String("func");
    auto k_struct = String("struct");
    auto k_main = String("main");

    modul.structDefs = cast(StructDef*) calloc(StructDef.sizeof, allocMAX);
    modul.funcDefs = cast(FuncDef*) calloc(FuncDef.sizeof, allocMAX);

    String* currentToken = tokens.ptr;
    while (currentToken.size != 0)
    {
        if (same(currentToken, &k_func))
        {
            auto s = modul.funcDefs + modul.funcDefsSize;
            s.parDefs = cast(VarDef*) calloc(VarDef.sizeof, allocMAX);
            s.statements = cast(Statement*) calloc(Statement.sizeof, allocMAX);
            currentToken = parseFunc(currentToken, s);
            modul.funcDefsSize = modul.funcDefsSize + 1;
            continue;
        }
        if (same(currentToken, &k_struct))
        {
            auto s = modul.structDefs + modul.structDefsSize;
            s.varDefs = cast(VarDef*) calloc(VarDef.sizeof, allocMAX);
            currentToken = parseStruct(currentToken, s);
            modul.structDefsSize = modul.structDefsSize + 1;
            continue;
        }
        printf("??MM '%.*s'  %ld\n", currentToken.size, currentToken.ptr, currentToken.ptr - startTT);
        currentToken = currentToken + 1;
    }
}

////////////////////////////////////////////////// PRINTTTTTTTT

void printStatement(Statement* stm, int32 tab)
{
    if (stm.type == StatementType.t_group || stm.type == StatementType.t_var || stm.type == StatementType.t_return)
    {
        if (stm.type == StatementType.t_var)
        {
            printf("var ");

        }
        if (stm.type == StatementType.t_return)
        {
            printf("return ");

        }
        Group* gg = cast(Group*) stm.ptr;
        int32 ww = 0;
        while (ww < gg.elementsSize)
        {
            GroupElement* ee = gg.elements + ww;
            printStatement(&ee.stm, tab);
            if (ee.op)
            {
                printf("%.*s", ee.op.size, ee.op.ptr);
            }
            ww++;
        }
    }
    else if (stm.type == StatementType.t_String)
    {

        String* ss = cast(String*) stm.ptr;
        printf("%.*s", ss.size, ss.ptr);
    }
    else if (stm.type == StatementType.t_funcCall)
    {
        FuncCall* ff = cast(FuncCall*) stm.ptr;
        printf("%.*s(", ff.name.size, ff.name.ptr);
        if (ff.group)
        {
            Statement st;
            st.ptr = ff.group;
            st.type = StatementType.t_group;
            printStatement(&st, tab);
        }
        printf(")");

    }
    else if (stm.type == StatementType.t_while)
    {
        While* wwW = cast(While*) stm.ptr;
        Statement st;
        st.ptr = &wwW.call;
        st.type = StatementType.t_funcCall;
        printStatement(&st, tab);

        printf("{\n");
        int32 ww = 0;
        tab++;
        while (ww < wwW.statementsSize)
        {
            Statement* ee = wwW.statements + ww;
            printf("%.*s", tab, "\t\t\t\t\t\t\t\t".ptr);
            printStatement(ee, tab);
            printf(";\n");
            ww++;
        }
        tab--;
        printf("%.*s}", tab, "\t\t\t\t\t\t\t\t".ptr);

    }
    else
    {
        printf("st(%d) %.*s", stm.type, StatementTypeNames[stm.type].length, StatementTypeNames[stm.type].ptr);
    }
}

void printModule(Module* modul)
{
    int32 i = 0;
    while (i < modul.structDefsSize)
    {
        StructDef* s = &modul.structDefs[i];
        printf("struct '%.*s' {\n", s.name.size, s.name.ptr);

        int32 kk = 0;
        while (kk < s.varDefsSize)
        {
            VarDef* v = &s.varDefs[kk];

            printf("\t%.*s(%d) %.*s;\n", v.type.size, v.type.ptr, v.isPtr, v.name.size, v.name.ptr);
            kk = kk + 1;
        }

        printf("}\n");
        i = i + 1;
    }

    printf("\n");
    i = 0;
    while (i < modul.funcDefsSize)
    {
        FuncDef* s = &modul.funcDefs[i];
        printf("func %.*s(", s.name.size, s.name.ptr);

        int32 kk = 0;
        while (kk < s.parDefsSize)
        {
            VarDef* v = &s.parDefs[kk];

            printf(" %.*s(%d) %.*s,", v.type.size, v.type.ptr, v.isPtr, v.name.size, v.name.ptr);
            kk = kk + 1;
        }

        printf(" ){\n");
        kk = 0;
        while (kk < s.statementsSize)
        {
            Statement* v = s.statements + kk;
            printf("\t");
            printStatement(v, 1);
            printf(";\n");

            kk = kk + 1;
        }
        printf("}\n");
        i = i + 1;
    }
}

////////////////////////////////////////////////// INTERPRET

void interpretStatement(Statement* stm)
{
    if (stm.type == StatementType.t_group)
    {
        Group* gg = cast(Group*) stm.ptr;
        int32 ww = 0;
        while (ww < gg.elementsSize)
        {
            GroupElement* ee = gg.elements + ww;
            interpretStatement(&ee.stm);
            if (ee.op)
            {
            }
            ww++;
        }
    }
    else if (stm.type == StatementType.t_funcCall)
    {
        auto k_printf = String("printf");
        FuncCall* ff = cast(FuncCall*) stm.ptr;
        if (same(ff.name, &k_printf))
        {
            String* str = cast(String*) ff.group.elements[0].stm.ptr;
            int8 tmp = str.ptr[str.size];
            str.ptr[str.size] = '\0';
            printf("'%s'\n", cast(char*) str.ptr);
            str.ptr[str.size] = tmp;
        }
    }
}

void interpretModule(Module* modul)
{
    int32 i = 0;
    while (i < modul.funcDefsSize)
    {
        FuncDef* s = &modul.funcDefs[i];
        int32 kk = 0;
        while (kk < s.statementsSize)
        {
            Statement* v = s.statements + kk;
            interpretStatement(v);
            kk = kk + 1;
        }
        i = i + 1;
    }
}
////////////////////////////////////////////////// GEN CODE

import llvm;

struct CompModule
{
    LLVMValueRef[string] functions;
    LLVMValueRef[string] values;
    LLVMModuleRef mod;
    LLVMBuilderRef builder;
    LLVMTypeRef stringType;
}

LLVMValueRef genGroup(Group* gg, CompModule* compModule, int start, ref int end)
{
    int32 ww = start;
    LLVMValueRef lastVal;
    char lastOp;
    while (gg && ww < gg.elementsSize)
    {
        GroupElement* ee = gg.elements + ww;

        LLVMValueRef val = genGroupElement(ee, compModule);
        if (lastVal != null)
        {
            if (lastOp == '+')
            {
                lastVal = LLVMBuildAdd(compModule.builder, lastVal, val, "tmp");
            }
            else if (lastOp == '-')
            {
                lastVal = LLVMBuildSub(compModule.builder, lastVal, val, "tmp");
            }
            else if (lastOp == '.')
            {
                lastVal = LLVMBuildExtractValue(compModule.builder, lastVal, 1, "gett");
            }
            else
            {
                assert(0);
            }
        }
        else
        {
            lastVal = val;
        }

        if (ee.op == null)
        {
            break;
        }
        if (ee.op.ptr[0] == ',')
        {
            break;
        }
        lastOp = ee.op.ptr[0];
        ww++;

      
        assert(lastOp == '+' || lastOp == '-' || lastOp == '.');
    }  
    end = ww;


    return lastVal;


}

LLVMValueRef genGroupElement(GroupElement* groupElement, CompModule* compModule)
{
    LLVMValueRef lastVal;
    if (groupElement.stm.type == StatementType.t_String)
    {
        String* s = cast(String*) groupElement.stm.ptr;
        int8 tmp = s.ptr[s.size];
        s.ptr[s.size] = '\0';
        if (s.ptr[0] == '"')
        {
            // printf("String Array:  '%.*s'\n", s.size, s.ptr);
            s.ptr[s.size - 1] = '\0';
            lastVal = LLVMBuildGlobalStringPtr(compModule.builder, cast(char*) s.ptr + 1, cast(char*) s.ptr + 1);
            s.ptr[s.size - 1] = '"';
        }
        else if (s.ptr[0] >= '0' && s.ptr[0] <= '9')
        {
            // printf("Number:  '%.*s'\n", s.size, s.ptr);
            int64 x = strtoll(cast(char*) s.ptr, null, 10);
            //printf("D %d\n", x);
            lastVal = LLVMConstInt(LLVMInt64Type(), x, true);

        }
        else
        {
            // printf("Var:  '%.*s' \n", s.size, s.ptr);
            string name = s.getString();
            lastVal = compModule.values[name];
        }
        s.ptr[s.size] = tmp;
    }
    else if (groupElement.stm.type == StatementType.t_funcCall)
    {
        return genStatement(&groupElement.stm, compModule);
    }
    else
    {
        assert(0);
    }
    return lastVal;
}

LLVMValueRef genStatement(Statement* stm, CompModule* compModule)
{
    if (stm.type == StatementType.t_group)
    {
        Group* gg = cast(Group*) stm.ptr;
        int32 ww = 0;
        while (ww < gg.elementsSize)
        {
            GroupElement* ee = gg.elements + ww;
            genStatement(&ee.stm, compModule);
            if (ee.op)
            {
            }
            ww++;
        }
    }
    else if (stm.type == StatementType.t_funcCall)
    {
        FuncCall* ff = cast(FuncCall*) stm.ptr;
        string ffName = ff.name.getString();
        printf("FunctionCall '%.*s'\n", ff.name.size, ff.name.ptr);
        LLVMValueRef[20] arguments;
        int argsLen;

        Group* gg = ff.group;
        int32 ww = 0;
        // char lastOp;
        while (gg && ww < gg.elementsSize)
        {
            LLVMValueRef lastVal;

            lastVal = genGroup(gg, compModule, ww, ww);
            GroupElement* ee = gg.elements + ww;
            assert(ee.op == null || ee.op.ptr[0] == ',');
            ww++;
            arguments[argsLen] = lastVal;
            LLVMDumpValue(lastVal);
            printf("\n");
            lastVal = null;
            argsLen++;

            if(ee.op == null){
                break;
            }
        }
        printf("FunCallEnd '%.*s' args(%d) \n", ff.name.size, ff.name.ptr, argsLen);

        auto fffff = compModule.functions[ffName];
        return LLVMBuildCall(compModule.builder, fffff, arguments.ptr, argsLen, ffName.toStringz());

    }
    else if (stm.type == StatementType.t_var)
    {
        Group* gg = cast(Group*) stm.ptr;
        assert(gg.elementsSize >= 2);

        GroupElement* firstElement = gg.elements;
        assert(firstElement.op.ptr[0]=='=');
        assert(firstElement.stm.type == StatementType.t_String);
        String* s = cast(String*) firstElement.stm.ptr;
        string valName = s.getString();

        int ww = 1;
        LLVMValueRef val = genGroup(gg, compModule, ww, ww);
        assert(ww + 1 == gg.elementsSize);

        printf("var '%.*s' = ", s.size, s.ptr);
        printf("\n");
        LLVMDumpValue(val);
        printf("\n");

        // LLVMValueRef val = genGroupElement(gg.elements + 1, compModule);
        compModule.values[valName] = val;
        return null;

    }
    else
    {
        assert(0);
    }
    return null;
}

void genModule(Module* modul)
{
    CompModule compMod;

    compMod.mod = LLVMModuleCreateWithName("my_module");
    compMod.builder = LLVMCreateBuilder();
    {
        LLVMTypeRef[] argsList = [LLVMPointerType(LLVMInt8Type(), 0)];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMInt32Type(), argsList.ptr, 0, true);
        compMod.functions["printf"] = LLVMAddFunction(compMod.mod, "printf", funcType);
    }
    {
        LLVMTypeRef[] argsList = [LLVMPointerType(LLVMInt8Type(), 0), LLVMPointerType(LLVMInt8Type(), 0)];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMPointerType(LLVMInt8Type(), 0), argsList.ptr, cast(int) argsList.length, false);
        compMod.functions["fopen"] = LLVMAddFunction(compMod.mod, "fopen", funcType);
        //FILE *fopen(const char *filename, const char *mode);
    }
    {
        LLVMTypeRef[] argsList = [LLVMPointerType(LLVMInt8Type(), 0), LLVMInt64Type(), LLVMInt32Type()];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMInt32Type(), argsList.ptr, cast(int) argsList.length, false);
        compMod.functions["fseek"] = LLVMAddFunction(compMod.mod, "fseek", funcType);
        //int fseek(FILE *file, long offset, int mode);
    }
    {
        LLVMTypeRef[] argsList = [LLVMPointerType(LLVMInt8Type(), 0)];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMInt64Type(), argsList.ptr, cast(int) argsList.length, false);
        compMod.functions["ftell"] = LLVMAddFunction(compMod.mod, "ftell", funcType);
    }
    {
        LLVMTypeRef[] argsList = [LLVMInt64Type(), LLVMInt64Type()];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMPointerType(LLVMInt8Type(), 0), argsList.ptr, cast(int) argsList.length, false);
        compMod.functions["calloc"] = LLVMAddFunction(compMod.mod, "calloc", funcType);
        //oid* calloc (size_t num, size_t size);
    }
    {
        LLVMTypeRef[] argsList = [LLVMPointerType(LLVMInt8Type(), 0), LLVMInt64Type(), LLVMInt64Type(), LLVMPointerType(LLVMInt8Type(), 0)];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMInt64Type(), argsList.ptr, cast(int) argsList.length, false);
        compMod.functions["fread"] = LLVMAddFunction(compMod.mod, "fread", funcType);
        //size_t fread(void* ptr, size_t size, size_t nitems, FILE* stream);
    }
    {
        LLVMTypeRef[] argsList = [LLVMPointerType(LLVMInt8Type(), 0)];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMInt32Type(), argsList.ptr, cast(int) argsList.length, false);
        compMod.functions["fclose"] = LLVMAddFunction(compMod.mod, "fclose", funcType);
    }

    {
        LLVMTypeRef[] argsList = [LLVMInt64Type()];
        LLVMTypeRef funcType = LLVMFunctionType(LLVMInt32Type(), argsList.ptr, cast(int) argsList.length, false);
        LLVMValueRef func = LLVMAddFunction(compMod.mod, "i32", funcType);

        LLVMBasicBlockRef entry = LLVMAppendBasicBlock(func, "entry");

        LLVMPositionBuilderAtEnd(compMod.builder, entry);

        auto val = LLVMBuildIntCast2(compMod.builder, LLVMGetParam(func, 0), LLVMInt32Type(), false, "int64toint32");

        LLVMBuildRet(compMod.builder, val);

        compMod.functions["i32"] = func;
    }

    {
        LLVMTypeRef[] structTypes = [LLVMPointerType(LLVMInt8Type(), 0), LLVMInt64Type()];
        compMod.stringType = LLVMStructType(structTypes.ptr, cast(int) structTypes.length, false);

        LLVMTypeRef funcType = LLVMFunctionType(compMod.stringType, null, 0, false);
        LLVMValueRef func = LLVMAddFunction(compMod.mod, "String", funcType);

        LLVMBasicBlockRef entry = LLVMAppendBasicBlock(func, "entry");

        LLVMPositionBuilderAtEnd(compMod.builder, entry);

        LLVMValueRef[] values = [LLVMConstNull(LLVMInt8Type()), LLVMConstInt(LLVMInt64Type(), 0, true)];
        auto val = LLVMConstNamedStruct(compMod.stringType, values.ptr, cast(int) values.length);
        auto vint = LLVMConstInt(LLVMInt64Type(), 5, true);
        auto val22 = LLVMBuildInsertValue (compMod.builder, val, vint, 1, "ss");

        LLVMBuildRet(compMod.builder, val22);

        compMod.functions["String"] = func;
    }

    // auto f = fopen("test.nlang", "rb");
    // fseek(f, 0, seek_end);
    // auto fsize = ftell(f);
    // fseek(f, 0, seek_set);
    // auto str = calloc(1, fsize + 1);
    // fread(str, 1, fsize, f);
    // fclose(f);

    // LLVMValueRef sum = LLVMAddFunction(mod, "main", ret_type);

    int32 i = 0;
    while (i < modul.funcDefsSize)
    {
        FuncDef* s = &modul.funcDefs[i];

        String* str = s.name;
        printf("GG %.*s\n", str.size, str.ptr);
        int8 tmp = str.ptr[str.size];
        str.ptr[str.size] = '\0';

        // LLVMTypeRef[] param_types = [LLVMInt32Type(), LLVMInt32Type()];
        LLVMTypeRef[] param_types = [];
        LLVMTypeRef ret_type = LLVMFunctionType(LLVMVoidType(), param_types.ptr, 0, 0);
        LLVMValueRef func = LLVMAddFunction(compMod.mod, cast(char*)(str.ptr), ret_type);
        printf("'%s'\n", cast(char*) str.ptr);
        str.ptr[str.size] = tmp;

        LLVMBasicBlockRef entry = LLVMAppendBasicBlock(func, "entry");

        LLVMPositionBuilderAtEnd(compMod.builder, entry);

        int32 kk = 0;
        while (kk < s.statementsSize)
        {
            Statement* v = s.statements + kk;
            genStatement(v, &compMod);
            kk = kk + 1;
        }
        i = i + 1;

        LLVMBuildRetVoid(compMod.builder);
    }

    char* error = null;
    LLVMVerifyModule(compMod.mod, LLVMAbortProcessAction, &error);
    LLVMDisposeMessage(error);

    LLVMExecutionEngineRef engine;
    error = null;

    LLVMInitializeNativeTarget();
    if (LLVMCreateExecutionEngineForModule(&engine, compMod.mod, &error) != 0)
    {
        fprintf(stderr, "failed to create execution engine\n");
        abort();
    }
    if (error)
    {
        fprintf(stderr, "error: %s\n", error);
        LLVMDisposeMessage(error);
        exit(EXIT_FAILURE);
    }

    // Write out bitcode to file
    if (LLVMWriteBitcodeToFile(compMod.mod, "mmm.bc") != 0)
    {
        fprintf(stderr, "error writing bitcode to file, skipping\n");
    }

    LLVMDisposeBuilder(compMod.builder);
    LLVMDisposeExecutionEngine(engine);
}

int8* startTT;

void main()
{
    String fileContent;
    Tokens tokens;
    Module modul;
    loadFile(&fileContent);
    startTT = fileContent.ptr;
    tokenize(&tokens, &fileContent);
    makeModule(&modul, &tokens);

    // printTokens(&tokens);
    printModule(&modul);
    interpretModule(&modul);
    genModule(&modul);

}
// rdmd -g  -L-lLLVM-8 -version=LLVM_8_0_0 -verrors=context -checkaction=context workaround.o src/lexer.d
// rdmd -g  -L-lLLVM-8 -version=LLVM_8_0_0 src/lexer.d
// llc-8 -relocation-model=pic -filetype=obj mmm.bc && gcc mmm.o && ./a.out 
// llvm-dis-8 mmm.bc


//rdmd -g -L-lLLVM-8 -Illvm-d-master/source/ -version=LLVM_8_0_0  test.d 1 2 && llc-8 -relocation-model=pic -filetype=obj sum.bc && gcc sum.o && ./a.out

//nasm -w+all -f elf32 -o _exit.o _exit.asm && ld -m elf_i386 -o _exit _exit.o && ./_exit ; echo $?

// ld -m elf_i386 -o pp sum.o