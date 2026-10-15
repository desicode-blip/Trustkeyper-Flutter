import { test } from 'node:test';
import assert from 'node:assert/strict';
import { linkedInProfile } from '../linkedin-profile.js';

test('LinkedIn normalizes personal URLs and accepts an explicit optional skip', () => {
  assert.deepEqual(linkedInProfile({ url: 'linkedin.com/in/test-person/?tracking=one' }), { url: 'https://www.linkedin.com/in/test-person', skipped: false });
  assert.deepEqual(linkedInProfile({ url: '', skipped: true }), { url: '', skipped: true });
});
test('LinkedIn rejects credential URLs, other hosts and non-person pages', () => {
  for (const url of ['', 'example.com/in/test', 'linkedin.com.evil.test/in/test', 'https://user@linkedin.com/in/test', 'linkedin.com/company/test', 'javascript:alert(1)']) {
    assert.throws(() => linkedInProfile({ url }));
  }
});
