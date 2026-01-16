# License

## Build Tooling License

Copyright 2026 Infoblox Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## Upstream License Notice

**⚠️ IMPORTANT: Confluent Community License Restrictions**

This repository contains build tooling only. The actual Confluent Schema Registry source code is referenced via Git submodule at `upstream/schema-registry` and is subject to the [Confluent Community License](https://github.com/confluentinc/schema-registry/blob/master/LICENSE).

### Key Restrictions

The Confluent Community License Agreement **PROHIBITS**:

- Providing the software to third parties as a **hosted or managed service** where the software provides substantial value
- Circumventing license key functionality or removing/obscuring features protected by license keys

### What This Means for Users

- ✅ **Allowed**: Building and running Schema Registry containers for internal use within your organization
- ✅ **Allowed**: Using Schema Registry as part of your application infrastructure
- ✅ **Allowed**: Modifying build tooling in this repository (MIT licensed)
- ❌ **Prohibited**: Offering Schema Registry as a managed service to external customers
- ❌ **Prohibited**: Providing Schema Registry hosting to third parties for compensation

### Full License Text

For the complete license terms, see:
- Confluent Community License: https://github.com/confluentinc/schema-registry/blob/master/LICENSE
- Schema Registry Licensing: https://docs.confluent.io/platform/current/installation/license.html

### Disclaimer

**This is not legal advice.** Users are responsible for ensuring their use complies with the Confluent Community License. If you plan to use Schema Registry in a commercial context, consult with your legal counsel to understand the restrictions.

---

## Compliance

This repository complies with Confluent's licensing by:

1. **Not copying upstream code**: Schema Registry source is referenced via Git submodule only
2. **Clear license notices**: This document prominently displays upstream license restrictions
3. **Tooling separation**: Build infrastructure (Dockerfile, Makefile, CI) is MIT licensed separately
4. **Documentation**: README and quickstart guides link to official Confluent licensing documentation

If you believe this repository violates any license terms, please open an issue immediately.
