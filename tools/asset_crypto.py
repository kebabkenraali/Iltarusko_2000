#!/usr/bin/env python3
"""Encrypt/decrypt the local asset package used by install.ps1.

Package layout:
    MAGIC(8) | salt(16) | nonce(16) | ciphertext | HMAC-SHA256(32)

Key = PBKDF2-HMAC-SHA256(passphrase, salt, 200000, 32 bytes).
Keystream = HMAC-SHA256(key, nonce || 64-bit counter) blocks (CTR-like).
The HMAC covers the whole header and ciphertext, so a wrong passphrase or a
modified package is detected before any file is written.

This is obfuscation/protection for a locally shipped asset archive, not DRM.
Usage:
    python tools/asset_crypto.py encrypt --in plain.zip --out packed.t2k --passphrase-file key.txt
    python tools/asset_crypto.py decrypt --in packed.t2k --out plain.zip --passphrase-file key.txt
"""
import argparse
import hashlib
import hmac
import os
import sys

MAGIC = b'T2KENC01'
SALT_LEN = 16
NONCE_LEN = 16
MAC_LEN = 32
ITERATIONS = 200_000


def derive(passphrase, salt):
    return hashlib.pbkdf2_hmac('sha256', passphrase.encode('utf-8'), salt, ITERATIONS, dklen=32)


def keystream(key, nonce, length):
    out = bytearray()
    counter = 0
    while len(out) < length:
        out += hmac.new(key, nonce + counter.to_bytes(8, 'big'), hashlib.sha256).digest()
        counter += 1
    return bytes(out[:length])


def xor(data, stream):
    return bytes(a ^ b for a, b in zip(data, stream))


def encrypt(data, passphrase):
    salt = os.urandom(SALT_LEN)
    nonce = os.urandom(NONCE_LEN)
    key = derive(passphrase, salt)
    ct = xor(data, keystream(key, nonce, len(data)))
    header = MAGIC + salt + nonce + ct
    mac = hmac.new(key, header, hashlib.sha256).digest()
    return header + mac


def decrypt(blob, passphrase):
    prefix = len(MAGIC) + SALT_LEN + NONCE_LEN
    if len(blob) < prefix + MAC_LEN or blob[:len(MAGIC)] != MAGIC:
        raise ValueError('not a T2K encrypted asset package')
    salt = blob[len(MAGIC):len(MAGIC) + SALT_LEN]
    nonce = blob[len(MAGIC) + SALT_LEN:prefix]
    ct = blob[prefix:-MAC_LEN]
    mac = blob[-MAC_LEN:]
    key = derive(passphrase, salt)
    expected = hmac.new(key, blob[:-MAC_LEN], hashlib.sha256).digest()
    if not hmac.compare_digest(expected, mac):
        raise ValueError('wrong passphrase or package corrupted')
    return xor(ct, keystream(key, nonce, len(ct)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=['encrypt', 'decrypt'])
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', dest='out', required=True)
    ap.add_argument('--passphrase-file', required=True)
    args = ap.parse_args()
    with open(args.passphrase_file, 'r', encoding='utf-8') as fh:
        pw = fh.read().strip()
    if not pw:
        ap.error('passphrase file is empty')
    with open(args.inp, 'rb') as fh:
        data = fh.read()
    result = encrypt(data, pw) if args.action == 'encrypt' else decrypt(data, pw)
    with open(args.out, 'wb') as fh:
        fh.write(result)
    print('%s: %d bytes -> %d bytes' % (args.action, len(data), len(result)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
