# Copyright (c) 2017 Wind River Systems Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Create a package for the toaster aggregator so it can packaged using pex"""
from setuptools import setup, find_packages

setup(
    name="toaster_aggregator",
    version="0.1",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'pyramid==1.8.2',
        'requests>=2.9.0',
        'pyramid_debugtoolbar',
        'pyramid_jinja2',
        'gunicorn',
    ],
    entry_points={
        'console_scripts': [
            'toaster_aggregator=gunicorn.app.wsgiapp:run'
        ],
        'paste.app_factory': [
            'main = toaster_aggregator.aggregator:main',
        ],
    },
    test_suite='nose.collector',
    tests_require=['nose'],
    author="Konrad Scherer",
    zip_safe=False,
    author_email="kmscherer@gmail.com",
    description="A webapp for aggregating toaster services listed by consul",
    license="MIT",
    url='http://github.com/Wind-River',
)
