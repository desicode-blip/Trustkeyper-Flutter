const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const functions = path.resolve(__dirname, '../functions');
const dependencies = path.join(functions, 'node_modules');
if (!fs.existsSync(dependencies)) {
  throw new Error('Install the locked Functions dependencies with npm --prefix functions ci.');
}

const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'trustkeyper-tk2-functions-'));
const source = path.join(directory, 'functions');
fs.mkdirSync(source);
for (const file of ['tk2.js', 'tk2-callables.js', 'package-lock.json']) {
  fs.copyFileSync(path.join(functions, file), path.join(source, file));
}

const manifest = JSON.parse(fs.readFileSync(path.join(functions, 'package.json'), 'utf8'));
manifest.main = 'tk2-callables.js';
fs.writeFileSync(path.join(source, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');
fs.symlinkSync(dependencies, path.join(source, 'node_modules'), process.platform === 'win32' ? 'junction' : 'dir');

const config = {
  functions: [{ source: 'functions', codebase: 'authentication', ignore: ['node_modules', '*.log'] }],
};
fs.writeFileSync(path.join(directory, 'firebase.json'), JSON.stringify(config, null, 2) + '\n');
console.log(directory);
