include "mexpr/ast.mc"
include "mexpr/pprint.mc"
include "string.mc"
include "jvm/ast.mc"
include "javascript/util.mc"
include "seq.mc"
include "pmexpr/utils.mc"
include "jvm/constants.mc"
include "stdlib.mc"
include "sys.mc"
include "map.mc"
include "mexpr/cmp.mc"
include "mexpr/lamlift.mc"
include "mexpr/type-annot.mc"
include "mexpr/type-lift.mc"
include "mexpr/shallow-patterns.mc"

lang MExprJVMCompile = MExprAst + JVMAst + MExprPrettyPrint + MExprCmp

    type JVMEnv = {
        bytecode : [Bytecode],
        vars : Map Name Int, 
        fieldVars : Map Name Field,
        localVars : Int, -- number of local vars on the JVM
        classes : [Class],
        name : String,
        nextClass : String,
        recordMap : Map Type (Map SID Int),
        adtTags : Map Name (String, Int),
        functions : [Function],
        args : Int
    }

    -- go through AST and translate to JVM bytecode

    sem toJSONExpr : JVMEnv -> Expr -> JVMEnv
    sem toJSONExpr env =
    | TmSeq { tms = tms } -> { env with bytecode = concat env.bytecode [ldcString_ (_charSeq2String tms)]} -- only for strings now
    | TmConst { val = val } -> 
        let bc = (match val with CInt { val = val } then 
            concat [ldcLong_ val] wrapInteger_
        else match val with CFloat { val = val } then
            concat [ldcFloat_ val] wrapFloat_ 
        else match val with CBool { val = val } then 
            match val with true then
                concat [ldcInt_ 1] wrapBoolean_
            else 
                concat [ldcInt_ 0] wrapBoolean_
        else match val with CChar { val = val } then
            wrapChar_ [ldcInt_ (char2int val)]
        else never)
        in { env with bytecode = concat env.bytecode bc }
    | TmApp { lhs = lhs, rhs = rhs, ty = ty } ->
        let to = ty in 
        let arg = toJSONExpr { env with bytecode = [], classes = [], functions = [] } rhs in
        match lhs with TmConst _ then 
            -- this could be a Map?
            match lhs with TmConst { val = CAddi _ } then 
                applyFun_ env "addi" arg
            else match lhs with TmConst { val = CSubi _ } then 
                applyFun_ env "subi" arg
            else match lhs with TmConst { val = CMuli _ } then 
                applyFun_ env "muli" arg
            else match lhs with TmConst { val = CDivi _ } then 
                applyFun_ env "divi" arg
            else match lhs with TmConst { val = CModi _ } then 
                applyFun_ env "modi" arg
            else match lhs with TmConst { val = CAddf _ } then 
                applyFun_ env "addf" arg
            else match lhs with TmConst { val = CSubf _ } then 
                applyFun_ env "subf" arg
            else match lhs with TmConst { val = CMulf _ } then 
                applyFun_ env "mulf" arg
            else match lhs with TmConst { val = CDivf _ } then 
                applyFun_ env "divf" arg
            else match lhs with TmConst { val = CEqi _ } then
                applyFun_ env "eqi" arg
            else match lhs with TmConst { val = CNeqi _ } then
                applyFun_ env "neqi" arg
            else match lhs with TmConst { val = CLti _ } then
                applyFun_ env "lti" arg
            else match lhs with TmConst { val = CGti _ } then
                applyFun_ env "gti" arg
            else match lhs with TmConst { val = CLeqi _ } then
                applyFun_ env "leqi" arg
            else match lhs with TmConst { val = CGeqi _ } then
                applyFun_ env "geqi" arg
            else match lhs with TmConst { val = CEqf _ } then
                applyFun_ env "eqf" arg
            else match lhs with TmConst { val = CNeqf _ } then
                applyFun_ env "neqf" arg
            else match lhs with TmConst { val = CLtf _ } then
                applyFun_ env "ltf" arg
            else match lhs with TmConst { val = CGtf _ } then
                applyFun_ env "gtf" arg
            else match lhs with TmConst { val = CLeqf _ } then
                applyFun_ env "leqf" arg
            else match lhs with TmConst { val = CGeqf _ } then
                applyFun_ env "geqf" arg
            else match lhs with TmConst { val = CSlli _ } then
                applyFun_ env "slli" arg
            else match lhs with TmConst { val = CSrli _ } then
                applyFun_ env  "srli" arg
            else match lhs with TmConst { val = CSrai _ } then
                applyFun_ env  "srai" arg
            else match lhs with TmConst { val = CNegf _ } then
                oneArgOpF_ dneg_ env arg
            else match lhs with TmConst { val = CNegi _ } then
                oneArgOpI_ lneg_ env arg
            else match lhs with TmConst { val = CEqc _ } then
                applyFun_ env "eqc" arg
            else match lhs with TmConst { val = CRandSetSeed _ } then
                { env with bytecode = foldl concat 
                                env.bytecode 
                                [[getstatic_ (concat pkg_ "Main") "random" "Ljava/util/Random;"],
                                arg.bytecode,
                                unwrapInteger_,
                                [invokevirtual_ "java/util/Random" "setSeed" "(J)V"],
                                nothing_],
                            classes = concat env.classes arg.classes,
                            functions = concat env.functions arg.functions }
            else match lhs with TmConst { val = CRandIntU _ } then
                applyFun_ env "rand" arg
            else 
                (print "Unknown Const!\n");
                env
        -- if type of arg is Record -> Array
        else -- new func aload 0...n invokedynamic keep count of args
            let fun = toJSONExpr env lhs in
            let argT = join (map (lam i. object_LT) (create env.args (lam i. i))) in
            let fun = toJSONExpr env lhs in 
            { fun with 
                bytecode = foldl concat fun.bytecode 
                    [arg.bytecode, 
                    [checkcast_ object_T],
                    [invokeinterface_ (concat pkg_ "Function") "apply" "(Ljava/lang/Object;)Ljava/lang/Object;"]], 
                    classes = concat fun.classes arg.classes, 
                    functions = concat fun.functions arg.functions,
                    args = (match lhs with TmApp _ then addi env.args 1 else 0) }
    | TmLet { ident = ident, body = body, inexpr = inexpr, tyBody = tyBody } -> 
        let b = toJSONExpr { env with fieldVars = mapEmpty nameCmp } body in
        toJSONExpr { b with 
                        bytecode = snoc b.bytecode (astore_ env.localVars), 
                        fieldVars = mapEmpty nameCmp, 
                        localVars = addi 1 env.localVars, 
                        vars = mapInsert ident env.localVars env.vars } inexpr
    | TmLam { ident = ident, body = body } ->
        let funcName = createName_ "func" in 
        match env.name with "Main" then
            let bodyEnv = toJSONExpr { env with bytecode = [], functions = [], localVars = 2, vars = mapInsert ident 1 (mapEmpty nameCmp), name = funcName } body in 
            { env with 
                bytecode = concat env.bytecode [aload_ 0, invokedynamic_ (methodtype_T (type_LT (concat pkg_ "Program")) (type_LT (concat pkg_ "Function"))) funcName (methodtype_T object_LT object_LT)],
                functions = snoc (concat env.functions bodyEnv.functions) (createFunction funcName (methodtype_T object_LT object_LT) (snoc bodyEnv.bytecode areturn_)),
                classes = concat env.classes bodyEnv.classes }
        else 
            let bodyEnv = toJSONExpr { env with bytecode = [], functions = [], name = funcName, localVars = addi env.localVars 1, vars = mapInsert ident env.localVars env.vars } body in 
            let loads = foldli (lam acc. lam i. lam tup. concat acc [aload_ (addi i 1)]) [aload_ 0] (mapToSeq env.vars) in
            let ifargs = foldl (lam acc. lam tup. concat acc object_LT) (type_LT (concat pkg_ "Program")) (mapToSeq env.vars) in
            let ifdesc = join ["(", ifargs, ")", type_LT (concat pkg_ "Function")] in
            let fargs = foldl (lam acc. lam tup. concat acc object_LT) object_LT (mapToSeq env.vars) in 
            let fdesc = join ["(", fargs, ")", object_LT] in
            { env with 
                bytecode = foldl concat env.bytecode [loads, [invokedynamic_ ifdesc funcName fdesc]],
                functions = snoc (concat env.functions bodyEnv.functions) (createFunction funcName fdesc (snoc bodyEnv.bytecode areturn_)),
                classes = concat env.classes bodyEnv.classes }
    | TmVar { ident = ident } -> 
        let store = (match mapLookup ident env.vars with Some i then
            [aload_ i]
        else match mapLookup ident env.fieldVars with Some field then 
            -- do fieldlookup
            [aload_ 0, getfield_ (concat pkg_ env.name) (getNameField field) "Ljava/lang/Object;"]
        else
            (print (join ["No identifier! ", nameGetStr ident, "\n"]));
            []) in
        { env with bytecode = concat env.bytecode store }
    | TmMatch { target = target, pat = pat, thn = thn, els = els } -> 
        let targetEnv = toJSONExpr env target in
        jvmPat targetEnv (tyTm target) thn els pat
    | TmRecord { bindings = bindings, ty = ty } ->
        let mapSeq = mapToSeq bindings in
        let len = length mapSeq in
        match mapLookup ty env.recordMap with Some translation then
            let insertBytecode = foldl (
                lam e. lam tup.
                    let expr = (match mapLookup tup.0 bindings with Some e then e else never) in
                    let exprEnv = toJSONExpr { e with bytecode = concat e.bytecode [dup_, ldcInt_ tup.1] } expr in 
                    { e with 
                        bytecode = snoc exprEnv.bytecode aastore_, 
                        classes = concat e.classes exprEnv.classes, 
                        functions = concat e.functions exprEnv.functions,
                        recordMap = mapUnion e.recordMap exprEnv.recordMap }
            ) { env with bytecode = [], classes = [] } (mapToSeq translation) in
            let recordBytecode = concat [ldcInt_ len, anewarray_ object_T] insertBytecode.bytecode in
            { env with 
                bytecode = concat env.bytecode (wrapRecord_ recordBytecode), 
                functions = concat env.functions insertBytecode.functions,
                classes = concat env.classes insertBytecode.classes,
                recordMap = mapUnion env.recordMap insertBytecode.recordMap }
        else
            let sidInt = mapi (lam i. lam tup. (tup.0, i)) mapSeq in
            let sidIntMap = mapFromSeq cmpSID sidInt in
            let insertBytecode = foldl (
                lam e. lam tup.
                    let expr = (match mapLookup tup.0 bindings with Some e then e else never) in
                    let exprEnv = toJSONExpr { e with bytecode = concat e.bytecode [dup_, ldcInt_ tup.1] } expr in 
                    { e with 
                        bytecode = snoc exprEnv.bytecode aastore_, 
                        functions = concat e.functions exprEnv.functions,
                        classes = concat e.classes exprEnv.classes, 
                        recordMap = mapUnion e.recordMap exprEnv.recordMap }
            ) { env with bytecode = [], classes = [], functions = [] } sidInt in
            let recordBytecode = concat [ldcInt_ len, anewarray_ object_T] insertBytecode.bytecode in
            let rm = mapInsert ty sidIntMap env.recordMap in 
            { env with 
                bytecode = concat env.bytecode (wrapRecord_ recordBytecode), 
                functions = concat env.functions insertBytecode.functions,
                classes = concat env.classes insertBytecode.classes, 
                recordMap = mapUnion insertBytecode.recordMap rm }
    | TmRecLets _ -> (printLn "TmRecLets"); env
    | TmSeq _ -> (printLn "TmSeq"); env
    | TmRecordUpdate _ -> (printLn "TmRecordUpdate"); env
    | TmType _ -> (printLn "TmType: Should be gone"); env
    | TmConDef _ -> (printLn "TmConDef: Should be gone"); env
    | TmConApp { ident = ident, body = body } -> 
        let constructor = nameGetStr ident in
        let bodyEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } body in
        { env with 
            bytecode = foldl concat 
                env.bytecode
                [initClass_ constructor,
                [dup_],
                bodyEnv.bytecode,
                [checkcast_ object_T, putfield_ (concat pkg_ constructor) "value" object_LT]],
            classes = concat bodyEnv.classes env.classes,
            functions = concat bodyEnv.functions env.functions,
            recordMap = mapUnion env.recordMap bodyEnv.recordMap }
    | TmUtest _ -> (printLn "TmUtest"); env
    | TmNever _ -> { env with bytecode = concat env.bytecode [new_ "java/lang/Exception", dup_, ldcString_ "Never Reached!", invokespecial_ "java/lang/Exception" "<init>" "(Ljava/lang/String;)V"] }
    | TmExt _ -> (printLn "TmExt"); env
    | a -> 
        (print "unknown expr\n");
        env

    sem jvmPat : JVMEnv -> Type -> Expr -> Expr -> Pat -> JVMEnv
    sem jvmPat env targetty thn els =
    | PatInt { val = val } ->
        let thnEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } thn in
        let elsEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } els in
        let elsLabel = createName_ "els" in
        let endLabel = createName_ "end" in
        { env with 
            bytecode = foldl concat 
                    env.bytecode 
                    [unwrapInteger_,
                    [ldcLong_ val, 
                    lcmp_, 
                    ifne_ elsLabel], 
                    thnEnv.bytecode, 
                    [goto_ endLabel,
                    label_ elsLabel], 
                    elsEnv.bytecode, 
                    [label_ endLabel]],
            classes = foldl concat env.classes [thnEnv.classes, elsEnv.classes],
            functions = foldl concat env.functions [thnEnv.functions, elsEnv.functions] }
    | PatRecord { bindings = bindings, ty = ty } ->
        match eqi (cmpType targetty ty) 0 with true then
            match mapLookup ty env.recordMap with Some r then 
                let patEnv = foldl 
                        (lam e. lam tup.
                            let sid = tup.0 in
                            let pat = tup.1 in 
                            match pat with PatNamed { ident = ident } then
                                match ident with PName name then 
                                    match mapLookup sid r with Some i then 
                                        { e with 
                                            bytecode = foldl concat e.bytecode [[dup_], unwrapRecord_, [ldcInt_ i, aaload_, astore_ e.localVars]],
                                            localVars = addi 1 e.localVars,
                                            vars = mapInsert name e.localVars e.vars } 
                                    else never
                                else never -- Wildcard!
                            else never) 
                        env
                        (mapToSeq bindings) in
                toJSONExpr { patEnv with bytecode = snoc patEnv.bytecode pop_ } thn 
            else never -- this records has not been encountered before?
        else 
            toJSONExpr env els
    | PatBool { val = val } ->
        let thnEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } thn in
        let elsEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } els in
        let elsLabel = createName_ "els" in
        let endLabel = createName_ "end" in
        let boolVal = (match val with true then 1 else 0) in
        { env with 
            bytecode = foldl concat 
                    env.bytecode 
                    [unwrapBoolean_,
                    [ldcInt_ boolVal,
                    ificmpne_ elsLabel], 
                    thnEnv.bytecode, 
                    [goto_ endLabel,
                    label_ elsLabel], 
                    elsEnv.bytecode, 
                    [label_ endLabel]],
            classes = foldl concat env.classes [thnEnv.classes, elsEnv.classes],
            functions = foldl concat env.functions [thnEnv.functions, elsEnv.functions] }
    | PatChar { val = val } ->
        let thnEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } thn in
        let elsEnv = toJSONExpr { env with bytecode = [], classes = [], functions = [] } els in
        let elsLabel = createName_ "els" in
        let endLabel = createName_ "end" in
        let charVal = char2int val in
        { env with 
            bytecode = foldl concat 
                    env.bytecode 
                    [unwrapChar_,
                    [ldcInt_ charVal,
                    ificmpne_ elsLabel], 
                    thnEnv.bytecode, 
                    [goto_ endLabel,
                    label_ elsLabel], 
                    elsEnv.bytecode, 
                    [label_ endLabel]],
            classes = foldl concat env.classes [thnEnv.classes, elsEnv.classes],
            functions = foldl concat env.functions [thnEnv.functions, elsEnv.functions] }
    | PatCon { ident = ident, subpat = subpat } ->
        let typeTag = (match mapLookup ident env.adtTags with Some tup then tup else never) in
        let t = typeTag.0 in
        let tag = typeTag.1 in
        let elsLabel = createName_ "els" in
        let endLabel = createName_ "end" in
        let adtClassName = (concat pkg_ (nameGetStr ident)) in
        match subpat with PatNamed { ident = id } then 
            match id with PName name then 
                let patEnv = { env with 
                                bytecode = foldl concat 
                                    env.bytecode 
                                    [[dup_,
                                    instanceof_ (concat pkg_ t),
                                    ifeq_ elsLabel, -- jump if 0
                                    dup_, 
                                    checkcast_ (concat pkg_ t),
                                    invokeinterface_ (concat pkg_ t) "getTag" "()I",
                                    ldcInt_ tag,
                                    ificmpne_ elsLabel,
                                    checkcast_ adtClassName, 
                                    getfield_ adtClassName "value" object_LT,
                                    astore_ env.localVars]],
                                localVars = addi 1 env.localVars,
                                vars = mapInsert name env.localVars env.vars } in
                let thnEnv = toJSONExpr patEnv thn in
                let elsEnv = toJSONExpr { patEnv with bytecode = [], classes = [], functions = [] } els in
                { thnEnv with 
                    bytecode = foldl concat 
                        thnEnv.bytecode
                        [[goto_ endLabel,
                        label_ elsLabel,
                        pop_], 
                        elsEnv.bytecode,
                        [label_ endLabel]],
                    classes = concat thnEnv.classes elsEnv.classes,
                    functions = concat thnEnv.functions elsEnv.functions }
            else -- wildcard
                toJSONExpr { env with bytecode = snoc env.bytecode pop_ } els
        else never 
    | a -> 
        (printLn "Unknown Pat"); 
        env 

    sem getJavaType : Type -> String
    sem getJavaType =
    | TyInt _ -> "I"
    | a -> ""

    sem toJSONConst : JVMEnv -> Const -> JVMEnv
    sem toJSONConst env =
    | a -> 
        (print "unknown const\n");
        env

end

lang CombinedLang = MExprLowerNestedPatterns + MExprPrettyPrint + MExprJVMCompile + MExprLambdaLift + MExprTypeCheck end

let collectADTTypes = lam tlMapping. 
    use MExprJVMCompile in
    foldl (lam acc. lam tup. 
            let t = tup.1 in 
            match t with TyVariant { constrs = constrs } then -- ADT
                let classes = acc.1 in
                let interfaces = acc.0 in
                let name = nameGetStr tup.0 in
                let interf = createInterface name [] [createFunction "getTag" "()I" []] in
                let constrClasses = foldli (lam acc. lam i. lam tup.
                                        let interfName = acc.0 in 
                                        let tagLookup = mapInsert tup.0 (interfName, i) acc.2 in
                                        let classes = acc.1 in
                                        let constrName = nameGetStr tup.0 in
                                        let class = createClass
                                                        constrName
                                                        (concat pkg_ interfName)
                                                        [createField "value" object_LT]
                                                        defaultConstructor
                                                        [createFunction 
                                                            "getTag"
                                                            "()I"
                                                            [ldcInt_ i,
                                                            ireturn_]] in
                                        (interfName, snoc classes class, tagLookup)) (name, [], mapEmpty nameCmp) (mapToSeq constrs) in
                let tagLookup = foldl (lam a. lam tup. mapInsert tup.0 tup.1 a) acc.2 (mapToSeq constrClasses.2) in
                (snoc interfaces interf, concat classes constrClasses.1, tagLookup)
            else -- record
                acc
            ) ([], [], mapEmpty nameCmp) tlMapping

let compileJVMEnv = lam ast.
    use MExprJVMCompile in
    use MExprTypeLift in
    let tl = typeLift ast in
    let adt = collectADTTypes tl.0 in
    let tlAst = tl.1 in
    let objToObj = createInterface "Function" [] [createFunction "apply" "(Ljava/lang/Object;)Ljava/lang/Object;" []] in 
    let env = { bytecode = [], vars = mapEmpty nameCmp, localVars = 1, classes = [], fieldVars = mapEmpty nameCmp, name = "Main", nextClass = createName_ "Func", recordMap = mapEmpty cmpType, adtTags = adt.2, functions = [], args = 0 } in
    let compiledEnv = (toJSONExpr env tlAst) in
    let bytecode = concat compiledEnv.bytecode [pop_, return_] in
    --let bytecode = concat compiledEnv.bytecode [astore_ 0, getstatic_ "java/lang/System" "out" "Ljava/io/PrintStream;", aload_ 0, invokevirtual_ "java/io/PrintStream" "print" "(Ljava/lang/Object;)V", return_] in
    let progClass = createClass "Program" "" [] defaultConstructor (concat [createFunction "start" "()V" bytecode] (concat mainFuncs_ compiledEnv.functions)) in 
    let mainFunc = createFunction "main" "([Ljava/lang/String;)V" (concat (initClass_ "Program") [invokevirtual_ (concat pkg_ "Program") "start" "()V", return_]) in 
    let mainClass = createClass "Main" "" [] defaultConstructor [mainFunc] in
    let constClasses = concat constClassList_ adt.1 in
    let prog = createProg pkg_ (foldl concat compiledEnv.classes [constClasses, [mainClass, progClass]]) (snoc adt.0 objToObj) in
    prog 

let compileMCoreToJVM = lam ast. 
    use MExprJVMCompile in
    use MExprLambdaLift in
    use MExprTypeAnnot in
    use MExprTypeCheck in
    let typeFix = typeCheck ast in -- types dissapear in pattern lowering
    let liftedAst = liftLambdas typeFix in
    let jvmProgram = compileJVMEnv liftedAst in
    (print (toStringProg jvmProgram));
    "aaa"

let getJarFiles = lam tempDir.
    (sysRunCommand ["wget", "-P", tempDir, "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-core/2.14.2/jackson-core-2.14.2.jar"] "" ".");
    (sysRunCommand ["wget", "-P", tempDir, "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-databind/2.14.2/jackson-databind-2.14.2.jar"] "" ".");
    (sysRunCommand ["wget", "-P", tempDir, "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-annotations/2.14.2/jackson-annotations-2.14.2.jar"] "" ".");
    (sysRunCommand ["wget", "-P", tempDir, "https://repo1.maven.org/maven2/org/ow2/asm/asm/9.4/asm-9.4.jar"] "" ".");
    ()

let compileJava = lam outDir. lam jarPath.
    let cfmClass = (concat stdlibLoc "/jvm/codegen/ClassfileMaker.java") in
    let jsonParserClass = (concat stdlibLoc "/jvm/codegen/Parser.java") in
    let classpath = (join [jarPath, "jackson-annotations-2.14.2.jar:", jarPath, "jackson-core-2.14.2.jar:", jarPath, "jackson-databind-2.14.2.jar:", jarPath, "asm-9.4.jar"]) in
    (sysRunCommand ["javac", "-cp", classpath, cfmClass, jsonParserClass, "-d", outDir] "" ".");
    ()

let modifyMainClassForTest = lam prog.
    use MExprJVMCompile in
    match prog with JVMProgram p in
    let mainClass = get p.classes (subi (length p.classes) 1) in
    match mainClass with Class m in
    let mainFunc = get m.functions 0 in
    match mainFunc with Function f in
    let bytecodes = subsequence f.bytecode 0 (subi (length f.bytecode) 2) in
    let modifiedMainFunc = createFunction f.name f.descriptor (concat bytecodes [astore_ 0, getstatic_ "java/lang/System" "out" "Ljava/io/PrintStream;", aload_ 0, invokevirtual_ "java/io/PrintStream" "print" "(Ljava/lang/Object;)V", return_]) in
    let modifiedMainClass = createClass m.name m.implements m.fields m.constructor (snoc (subsequence m.functions 1 (length m.functions)) modifiedMainFunc) in
    createProg p.package (snoc (subsequence p.classes 0 (subi (length p.classes) 1)) modifiedMainClass) p.interfaces
    

let prepareForTests = lam path.
    match sysCommandExists "java" with false then 
        -- error!
        ()
    else
        (match sysFileExists path with true then
            (sysDeleteDir path);
            (sysRunCommand ["mkdir", path] "" ".");
            (sysRunCommand ["mkdir", (concat path "jar/")] "" ".");
            (sysRunCommand ["mkdir", (concat path "out/")] "" ".");
            ()
        else 
            (sysRunCommand ["mkdir", path] "" ".");
            ());
        (getJarFiles (concat path "jar/"));
        (compileJava (concat path "out/") (concat path "jar/"));
        ()

let jvmTmpPath = "/tmp/miking-jvm-backend/"

let testJVM = lam ast.
    use CombinedLang in
    let tc = typeCheck ast in
    let patternLowedAst = lowerAll tc in
    let typeFix = typeCheck patternLowedAst in
    let liftedAst = liftLambdas typeFix in
    let jvmProgram = compileJVMEnv liftedAst in
    let testJVMProgram = modifyMainClassForTest jvmProgram in
    let json = sysTempFileMake () in
    writeFile json (toStringProg testJVMProgram);
    let jarPath = (concat jvmTmpPath "jar/") in
    let classpath = (join [":", jarPath, "jackson-annotations-2.14.2.jar:", jarPath, "jackson-core-2.14.2.jar:", jarPath, "jackson-databind-2.14.2.jar:", jarPath, "asm-9.4.jar"]) in
    (sysRunCommand ["java", "-cp", (join [jvmTmpPath, "out/", classpath]), "codegen/Parser", json] "" jvmTmpPath);
    let results = sysRunCommand ["java", "pkg.Main"] "" jvmTmpPath in
    sysDeleteDir json;
    results.stdout

-- tests

mexpr
prepareForTests jvmTmpPath;

-- integer operations
utest testJVM (addi_ (int_ 1) (int_ 1)) with "2" in
utest testJVM (subi_ (int_ 0) (int_ 1)) with "-1" in
utest testJVM (divi_ (int_ 10) (int_ 5)) with "2" in
utest testJVM (muli_ (int_ 2) (int_ (negi 1))) with "-2" in
utest testJVM (modi_ (int_ 10) (int_ 2)) with "0" in
utest testJVM (negi_ (int_ 1)) with "-1" in 
utest testJVM (slli_ (int_ 3) (int_ 2)) with "12" in 
utest testJVM (srli_ (int_ 24) (int_ 3)) with "3" in 
utest testJVM (srai_ (negi_ (int_ 24)) (int_ 3)) with "-3" in 

-- integer boolean operations
utest testJVM (lti_ (int_ 20) (int_ 10)) with "false" in
utest testJVM (gti_ (int_ 20) (int_ 10)) with "true" in
utest testJVM (eqi_ (int_ 10) (int_ 10)) with "true" in
utest testJVM (neqi_ (int_ 10) (int_ 10)) with "false" in
utest testJVM (leqi_ (int_ 20) (int_ 20)) with "true" in
utest testJVM (geqi_ (int_ 1) (int_ 9)) with "false" in

-- float boolean operations
utest testJVM (ltf_ (float_ 10.0) (float_ 10.5)) with "true" in
utest testJVM (gtf_ (float_ 20.0) (float_ 10.0)) with "true" in
utest testJVM (eqf_ (float_ 10.0) (float_ 10.0)) with "true" in
utest testJVM (neqf_ (float_ 10.0) (float_ 10.0)) with "false" in
utest testJVM (leqf_ (float_ 0.505) (float_ 0.505)) with "true" in
utest testJVM (geqf_ (float_ 1.5) (float_ 1.0)) with "true" in

-- float operations
utest testJVM (addf_ (float_ 1.5) (float_ 1.0)) with "2.5" in
utest testJVM (subf_ (float_ 0.5) (float_ 1.0)) with "-0.5" in
utest testJVM (divf_ (float_ 5.0) (float_ 10.0)) with "0.5" in
utest testJVM (mulf_ (float_ 2.2) (float_ (negf 1.0))) with "-2.2" in
utest testJVM (negf_ (float_ 1.5)) with "-1.5" in

-- char operations
utest testJVM (eqc_ (char_ 'a') (char_ 'a')) with "true" in

-- lambdas and let ins
utest testJVM (bindall_ [ulet_ "g" (ulam_ "f" (ulam_ "x" (ulam_ "y" (appf2_ (var_ "f") (var_ "x") (var_ "y"))))), subi_ (int_ 3) (int_ 2)]) with "1" in
utest testJVM (bindall_ [ulet_ "a" (int_ 1), ulet_ "b" (int_ 1), addi_ (var_ "a") (var_ "b")]) with "2" in

-- pattern matching
utest testJVM (match_ (int_ 1) (pint_ 1) (int_ 10) (negi_ (int_ 10))) with "10" in
utest testJVM (match_ (int_ 1) (pint_ 5) (int_ 10) (negi_ (int_ 10))) with "-10" in
utest testJVM (match_ (bool_ true) (pbool_ true) (bool_ true) (bool_ false)) with "true" in
utest testJVM (match_ (bool_ false) (pbool_ true) (bool_ true) (bool_ false)) with "false" in
utest testJVM (match_ (char_ 'a') (pchar_ 'a') (bool_ true) (bool_ false)) with "true" in
utest testJVM (match_ (char_ 'a') (pchar_ 'b') (bool_ true) (bool_ false)) with "false" in
utest (
    use MExprAst in
    let target = record_add "a" (int_ 10) (record_ (tyrecord_ [("a", tyint_)]) [("a", int_ 10)]) in
    let bindings = mapInsert (stringToSid "a") (pvar_ "a") (mapEmpty cmpSID) in
    let pat = PatRecord { bindings = bindings, info = NoInfo (), ty = tyrecord_ [("a", tyint_)] } in
    let thn = var_ "a" in
    let els = never_ in
    testJVM (match_ target pat thn els)) 
with "10" in

-- ADTs
utest (
    use MExprSym in
    testJVM (symbolize (bindall_ [type_ "Tree" [] (tyvariant_ []),
                        condef_ "Node" (tyarrow_ (tytuple_ [tycon_ "Tree", tycon_ "Tree"]) (tycon_ "Tree")),
                        condef_ "Leaf" (tyarrow_ (tyint_) (tycon_ "Tree")),
                        ulet_ "tree" (conapp_ "Node" (utuple_ [conapp_ "Leaf" (int_ 1), conapp_ "Leaf" (int_ 2)])),
                        match_ (var_ "tree") (pcon_ "Node" (ptuple_ [pcon_ "Leaf" (pvar_ "l"), pcon_ "Leaf" (pvar_ "r")])) (addi_ (var_ "l") (var_ "r")) (never_)]))
    )
with "3" in

-- never
utest testJVM never_ with "java.lang.Exception: Never Reached!" in

-- random
utest testJVM (bindall_ [ulet_ "a" (randSetSeed_ (int_ 1000)), randIntU_ (int_ 1) (int_ 10)]) with "5" in

sysDeleteDir jvmTmpPath 

