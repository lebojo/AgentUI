// Run against the disposable iPhone + host fixture from remote-integration.py --hold.
// SERVE_SIM_ROOT is the serve-sim/dist directory; HEKA_SIM is the simulator UDID.
const assert = require('node:assert/strict');
const path = require('node:path');
const root = process.env.SERVE_SIM_ROOT;
const device = process.env.HEKA_SIM;
assert(root && device, 'Set SERVE_SIM_ROOT and HEKA_SIM to the test runtime and disposable simulator');
const native = require(path.join(root, 'native/serve-sim-native.node'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function nodes() {
    const result = [];
    function visit(items) { for (const item of items) { result.push(item); visit(item.children || []); } }
    visit(JSON.parse(await native.axDescribe(device)));
    return result;
}
const button = (items, name) => items.find(n => n.type === 'Button' && n.AXLabel === name && n.frame.x >= 0);
(async () => {
    const hid = new native.SimHID(device, path.join(root, 'simduo/serve-sim-duo-hid'));
    await hid.isFoldable();
    async function tap(name, checkSidebar = false) {
        const before = await nodes();
        const target = button(before, name);
        assert(target, `Missing button: ${name}`);
        const { width, height } = before.find(n => n.type === 'Application').frame;
        const x = (target.frame.x + target.frame.width / 2) / width;
        const y = (target.frame.y + target.frame.height / 2) / height;
        await hid.touch('begin', x, y, width, height, 0);
        await sleep(80);
        await hid.touch('end', x, y, width, height, 0);
        // Observe the transition too: checking only the final screen misses a push/pop flash.
        for (let attempt = 0; attempt < 8; attempt++) {
            await sleep(50);
            if (checkSidebar) {
                const current = await nodes();
                assert(current.some(n => n.AXLabel === 'Connecté à 127.0.0.1'), 'A hierarchy click restarted the connection');
                assert(!current.some(n => ['Continue sur ton Mac', 'Choisis un terminal'].includes(n.AXLabel)), 'A hierarchy click pushed the empty detail');
                assert(button(current, 'Mobile fixture'), 'A hierarchy click left the sidebar');
            }
        }
        await sleep(300);
    }
    try {
        let current = await nodes();
        if (button(current, 'Heka')) await tap('Heka');
        current = await nodes();
        assert(button(current, 'Mobile fixture'), 'This must be the isolated Mobile fixture workspace');
        for (let repeat = 0; repeat < 3; repeat++) {
            await tap('Mobile fixture', true);
            await tap('Mobile fixture', true);
        }
        if (!button(await nodes(), 'Principal')) await tap('Mobile fixture', true);
        await tap('Principal', true);
        await tap('Principal', true);
        if (!button(await nodes(), 'Terminal')) await tap('Principal', true);
        await tap('Terminal');
        await sleep(1000);
        current = await nodes();
        assert(current.some(n => n.AXLabel === 'Écran du terminal'), 'A plain shell is not mirrored as a terminal');
        await tap('Heka');
        await tap('Mobile fixture', true);
        await tap('Mobile fixture', true);
        await tap('Terminal');
        await sleep(1000);
        assert((await nodes()).some(n => n.AXLabel === 'Écran du terminal'), 'Reopening the selected terminal lost navigation');
        console.log('PASS project/worktree expansion never selects a terminal or reconnects');
        console.log('PASS real terminal selection, back navigation and repeated reopening');
    } finally {
        await hid.close();
    }
})().catch(error => { console.error(error); process.exitCode = 1; });
