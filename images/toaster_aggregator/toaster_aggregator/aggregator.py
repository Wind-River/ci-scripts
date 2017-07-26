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

"""Provides web and REST interface to scheduler"""
import logging
import threading
import atexit

from pyramid.config import Configurator
from pyramid.response import Response
from pyramid.httpexceptions import HTTPOk, HTTPServiceUnavailable
from pyramid.view import (
    view_config,
    view_defaults
    )

import requests

logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger('toaster_aggregator')


VERSION = '0.1.0'

# lock to control access to global vars
LOCK = threading.Lock()
# thread handler
AGG_THREAD = threading.Thread()
QUERY_INTERVAL = 15
AGG_QUERY_SUCCESS = False
PREFIX = '/'
CONSUL = ''
RUNNING_BUILDS = []
NUM_RUNNING_BUILDS = 0


def aggregate_toaster_builds():
    """Analyze build stats and generate building progress data from Toaster API.

    Query to CONSUL/v1/health/service/toaster, return JSON:
        Field "Checks" contains health state of Toaster service, can only start to query Toaster when status is "passing"
        Field "Service" contains Toaster ip address and port

    Query to Toaster-Address:Port/toastergui/api/building if Toaster service is health, return JSON:
        Field "task" contains building progess in the format of "finished-tasks:total tasks"

    """
    health_check_request = start_request(CONSUL + '/v1/health/service/toaster', 'CONSUL')
    if health_check_request is None:
        return

    running_builds = []
    health_states = health_check_request.json()
    for state in health_states:
        check_info = state["Checks"]
        service_info = state["Service"]
        build = {}
        build['id'] = service_info["ID"]
        build['progress'] = "Pre-Build"
        build['name'] = build['id'].split(':')[1]
        build['link'] = "Not Started"
        for check in check_info:
            checkid = "service:" + build['id']
            # If Toaster service is healthy, query it for build information
            if check["CheckID"] == checkid and check["Status"] == "passing":
                build['link'] = "<a href=http://%s:%s>Toaster</a>" \
                                % (service_info['Address'], str(service_info['Port']))
                toaster_endpoint_building = "http://%s:%s/toastergui/api/building" \
                                            % (service_info['Address'], str(service_info['Port']))
                toaster_request = start_request(toaster_endpoint_building, 'Toaster')
                if toaster_request is None:
                    break
                toaster_data = toaster_request.json().get('building')
                if toaster_data is not None and isinstance(toaster_data, list) and toaster_data:
                    progress_data = toaster_data[0].get('task')
                    if progress_data is not None and len(progress_data.split(':')) > 1 and float(progress_data.split(':')[1]) > 0:
                        build['progress'] = "{:.0%}".format(float(progress_data.split(':')[0]) / float(progress_data.split(':')[1]))

        running_builds.append(build)

    sorted_builds = {'data': sorted(running_builds, key=lambda build: build['progress'])}

    global AGG_QUERY_SUCCESS
    global RUNNING_BUILDS
    global NUM_RUNNING_BUILDS
    with LOCK:
        RUNNING_BUILDS = sorted_builds
        NUM_RUNNING_BUILDS = len(sorted_builds)
        AGG_QUERY_SUCCESS = True

    log.debug("Build analysis complete. Found %s running builds", NUM_RUNNING_BUILDS)
    restart_analysis_timer()


def start_request(endpoint, request_type):
    """Make query to API endpoints and call restarter in case of any failure."""
    global AGG_QUERY_SUCCESS
    try:
        request = requests.get(endpoint)
    except requests.ConnectionError:
        with LOCK:
            AGG_QUERY_SUCCESS = False
        restart_analysis_timer()
        log.debug("Connection to %s failed, tried to connect to a %s endpoint", endpoint, request_type)
        return None

    if request.status_code != 200:
        with LOCK:
            AGG_QUERY_SUCCESS = False
        restart_analysis_timer()
        log.debug("Request to %s failed, tried to connect to a %s endpoint", endpoint, request_type)
        return None

    return request


def restart_analysis_timer():
    """Restarter for aggregator_toaster_builds"""
    global AGG_THREAD
    AGG_THREAD = threading.Timer(QUERY_INTERVAL, aggregate_toaster_builds)
    AGG_THREAD.daemon = True
    AGG_THREAD.start()


def root(_):
    stats = {}
    with LOCK:
        stats = {'running': NUM_RUNNING_BUILDS}

    return {'stats': stats, 'prefix': PREFIX}


def running_builds_json(_):
    with LOCK:
        return RUNNING_BUILDS


def health(_):
    """ Return service unavailable until query from Redis is complete """
    if not AGG_QUERY_SUCCESS:
        return HTTPServiceUnavailable()
    return HTTPOk()


def main(global_config, **settings):
    """Main method"""
    config = Configurator(settings=settings)
    config.include('pyramid_jinja2')

    config.add_route('root', '/')
    config.add_view(root, route_name='root', renderer='templates/builds.jinja2')

    config.add_route('health', '/health')
    config.add_view(health, route_name='health')

    config.add_route('running_builds_json', '/running')
    config.add_view(running_builds_json, route_name='running_builds_json', renderer='json')

    config.add_static_view(name='static', path='toaster_aggregator:static')
    app = config.make_wsgi_app()

    global PREFIX
    PREFIX = settings.get('prefix', '/')

    global CONSUL
    CONSUL = settings.get('consul', 'http://consul:8500')

    def interrupt():
        log.debug("Cancelling Aggregator Thread Timer")
        AGG_THREAD.cancel()

    global AGG_THREAD
    AGG_THREAD = threading.Timer(1, aggregate_toaster_builds)
    AGG_THREAD.daemon = True
    AGG_THREAD.start()

    # When you kill app (SIGTERM), clear the trigger for the next thread
    atexit.register(interrupt)

    return app
