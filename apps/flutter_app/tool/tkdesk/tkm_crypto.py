"""TrustKeyper Match data tools.

keygen:  python3 tools/tkm_crypto.py keygen site/data/keys.json   (asks for the team passphrase)
write:   python3 tools/tkm_crypto.py write site/data leads.json "WhatsApp: PHF URGENT LIFE NEEDS"

`write` only needs the public key in keys.json, so reading sessions never need
the passphrase. Each run adds one encrypted file to site/data/batches and lists
it in site/data/index.json.
"""

import base64
import datetime as dt
import getpass
import json
import os
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

ITER = 250_000
OAEP = padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None)
b64 = lambda b: base64.b64encode(b).decode()


def keygen(path, passphrase):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pkcs8 = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    spki = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    salt, iv = os.urandom(16), os.urandom(12)
    aes = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=ITER).derive(passphrase.strip().encode())
    wrapped = AESGCM(aes).encrypt(iv, pkcs8, None)
    json.dump({"v": 1, "iter": ITER, "salt": b64(salt), "iv": b64(iv), "wrapped": b64(wrapped), "publicKey": b64(spki)}, open(path, "w"), indent=1)


def write(data_dir, leads_path, source):
    keys = json.load(open(os.path.join(data_dir, "keys.json")))
    pub = serialization.load_der_public_key(base64.b64decode(keys["publicKey"]))
    leads = json.load(open(leads_path))
    aes, iv = os.urandom(32), os.urandom(12)
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    batch = {
        "v": 1,
        "at": now,
        "source": source,
        "count": len(leads.get("tenants", [])) + len(leads.get("homes", [])),
        "key": b64(pub.encrypt(aes, OAEP)),
        "iv": b64(iv),
        "data": b64(AESGCM(aes).encrypt(iv, json.dumps(leads, ensure_ascii=False).encode(), None)),
    }
    name = f"{now}.json"
    os.makedirs(os.path.join(data_dir, "batches"), exist_ok=True)
    json.dump(batch, open(os.path.join(data_dir, "batches", name), "w"))
    index_path = os.path.join(data_dir, "index.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {"batches": []}
    index["batches"].append({"file": name, "at": now, "source": source, "count": batch["count"]})
    json.dump(index, open(index_path, "w"), indent=1)
    print(f"wrote {name}: {batch['count']} leads")


if __name__ == "__main__":
    if sys.argv[1] == "keygen":
        keygen(sys.argv[2], os.environ.get("TKM_PASS") or getpass.getpass("Team passphrase: "))
    elif sys.argv[1] == "write":
        write(sys.argv[2], sys.argv[3], sys.argv[4])
