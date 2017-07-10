# Ubuntu 16.04 WRLinux Builder Docker Image

This repository contains Dockerfile and scripts used to build the
Ubuntu 16.04 WRLinux builder docker image hosted on Docker Hub. This
image is part of the Wind River Linux Continuous Integration Project.

## Building the image

To build the image windriver/ubuntu1604_64 run:

    make ubuntu1604_64

To build the image with a different registry and tag run:

    make ubuntu1604_64 TAG=test REGISTRY=internal:5000

## Contributing

Contributions submitted must be signed off under the terms of the Linux
Foundation Developer's Certificate of Origin version 1.1. Please refer to:
   https://developercertificate.org

To submit a patch:

- Open a Pull Request on the GitHub project
- Optionally create a GitHub Issue describing the issue addressed by the patch


# License

MIT License

Copyright (c) 2017 Wind River Systems Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
