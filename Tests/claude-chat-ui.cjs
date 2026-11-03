// UI regression for the isolated Claude fixture created by remote-integration.py --hold.
const assert = require('node:assert/strict');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = process.env.SERVE_SIM_ROOT, device = process.env.HEKA_SIM;
assert(root && device, 'Set SERVE_SIM_ROOT and HEKA_SIM');
const native = require(path.join(root, 'native/serve-sim-native.node'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function nodes() {
    const result = [];
    function visit(items) { for (const n of items) { result.push(n); visit(n.children || []); } }
    visit(JSON.parse(await native.axDescribe(device)));
    return result;
}
(async () => {
    const hid = new native.SimHID(device, path.join(root, 'simduo/serve-sim-duo-hid'));
    await hid.isFoldable();
    async function tap(label, type = 'Button') {
        const current = await nodes();
        const n = current.find(n => n.AXLabel === label && n.type === type && n.frame.x >= 0);
        assert(n, `Missing ${type}: ${label}`);
        const app = current.find(n => n.type === 'Application').frame;
        const x = (n.frame.x + n.frame.width / 2) / app.width;
        const y = (n.frame.y + n.frame.height / 2) / app.height;
        await hid.touch('begin', x, y, app.width, app.height, 0);
        await sleep(80);
        await hid.touch('end', x, y, app.width, app.height, 0);
        await sleep(1000);
    }
    try {
        let current = await nodes();
        if (current.some(n => n.type === 'Button' && n.AXLabel === 'Heka')) await tap('Heka');
        await tap('Claude fixture');
        current = await nodes();
        assert(current.some(n => n.AXValue === 'Message à Claude'), 'Structured composer is not present');
        assert(current.some(n => n.AXLabel?.includes('STRUCTURED_REPLY')), 'Assistant transcript is not visible');
        assert(!current.some(n => n.AXLabel?.includes('TUI_NOISE')), 'Chat scraped the terminal TUI');
        assert(!current.some(n => n.type === 'RadioButton' && ['Chat', 'Terminal'].includes(n.AXLabel)), 'Mode picker leaked into the session toolbar');
        execFileSync('xcrun', ['simctl', 'io', device, 'screenshot', '/tmp/heka-claude-chat.png']);
        await tap('Réglages');
        current = await nodes();
        assert(current.some(n => n.AXLabel === 'Affichage des sessions'), 'Display preference is missing from Settings');
        await tap('Terminal', 'RadioButton');
        await tap('Terminé');
        current = await nodes();
        assert(!current.some(n => n.AXValue === 'Message à Claude'), 'Chat renderer stayed mounted in Terminal mode');
        execFileSync('xcrun', ['simctl', 'io', device, 'screenshot', '/tmp/heka-claude-terminal.png']);
        await tap('Réglages');
        await tap('Chat', 'RadioButton');
        await tap('Terminé');
        current = await nodes();
        assert(current.some(n => n.AXLabel?.includes('STRUCTURED_REPLY')), 'Changing render mode restarted or lost the agent session');
        assert(current.some(n => n.AXValue === 'Message à Claude'), 'Chat renderer did not return');
        console.log('PASS Claude conversation/prose/tools rendered without terminal UI');
        console.log('PASS render preference in Settings only; Chat → Terminal → Chat preserves the agent');
    } finally { await hid.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
