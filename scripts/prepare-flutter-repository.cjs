const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const source = path.resolve(__dirname, '..');
const destination = path.resolve(process.argv.find(value => value.startsWith('--destination='))?.slice(14) ?? '');
assert.ok(destination !== source && !destination.startsWith(source + path.sep), 'Use a separate empty checkout.');
const git = (directory, args) => execFileSync('git', ['-C', directory, ...args], { encoding: 'utf8' }).trim();
assert.equal(git(destination, ['remote', 'get-url', 'origin']), 'https://github.com/desicode-blip/Trustkeyper-Flutter.git');
assert.equal(git(destination, ['ls-files']), '', 'The destination must not contain tracked files yet.');
assert.ok(fs.readdirSync(destination).every(name => name === '.git'), 'Do not overwrite existing destination files.');
const candidates = [...new Set(execFileSync('git', ['-C', source, 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], { encoding: 'utf8' }).split('\0').filter(Boolean))];
const localOnly = [];
const copied = [];
const liveTestInstructions = /9999999999|8888888888|1111111111|2222222222|\b123456\b/;
const secret = /re_[A-Za-z0-9_-]{25,}|sk_live_[A-Za-z0-9]+|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"private_key"\s*:\s*"[^"\n]{20,}/;
const textExtensions = /\.(dart|js|cjs|mjs|json|md|yaml|yml|plist|entitlements|swift|sh|ps1|xcconfig|pbxproj|xml|kts|txt|lock|rb|svg)$|(?:^|\/)(Podfile|Gemfile)$/;

for (const relative of candidates) {
  const origin = path.resolve(source, relative);
  if (!fs.existsSync(origin) || !fs.lstatSync(origin).isFile()) continue;
  assert.ok(origin.startsWith(source + path.sep));
  assert.doesNotMatch(relative, /^(output|node_modules|api|lib|supabase|artifacts)\/|^apps\/mobile\//);
  assert.doesNotMatch(relative, /(?:^|\/)(?:\.env(?:\..*)?|\.secret\.local|credentials\.json|key\.properties)$|\.(?:p8|p12|jks|keystore|mobileprovision|aab|apk|ipa)$/i);
  const bytes = fs.readFileSync(origin);
  if (textExtensions.test(relative)) {
    const text = bytes.toString('utf8');
    assert.ok(!secret.test(text), `Review a possible secret before publishing: ${relative}`);
    const operationalFile = relative.startsWith('docs/') || /^scripts\/[^/]+\.cjs$/.test(relative);
    if (operationalFile && relative !== 'scripts/prepare-flutter-repository.cjs' && liveTestInstructions.test(text)) {
      localOnly.push(relative);
      continue;
    }
  }
  const target = path.resolve(destination, relative);
  assert.ok(target.startsWith(destination + path.sep));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(origin, target, fs.constants.COPYFILE_EXCL);
  const digest = crypto.createHash('sha256').update(bytes).digest('hex');
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex'), digest);
  copied.push({ path: relative, sha256: digest });
}

const evidence = path.join(source, 'output/maintenance');
fs.mkdirSync(evidence, { recursive: true });
fs.writeFileSync(path.join(evidence, 'flutter-repository-export.json'), JSON.stringify({ destination, copied, localOnly, secretsPublished: false, previousGitHistoryIncluded: false }, null, 2));
console.log(`Copied and hash-verified ${copied.length} source files; kept ${localOnly.length} operational files local. No Git history or private credentials copied.`);
