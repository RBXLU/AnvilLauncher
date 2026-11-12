// Расширение для скрипта Universal JIT в StikDebug, отправляется лаунчером перед стартом JVM.
// Рантайм Java просит память под код старой командой brk #0x69 (x1 = размер в байтах):
// подменяем её на JIT26PrepareRegion из Universal-скрипта.
let anvilDetachAfterFirstBr = false;

legacyCommands[0x69] = function (brkResponse) {
    x1 = x0;
    x0 = 0;
    JIT26PrepareRegion(brkResponse);
    if (anvilDetachAfterFirstBr) {
        JIT26Detach();
    }
};

commands[3] = function (brkResponse) {
    anvilDetachAfterFirstBr = x0 != 0;
    log(`Anvil: detach after first brk = ${anvilDetachAfterFirstBr}`);
};
