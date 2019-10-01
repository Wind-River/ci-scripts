"""Update or create a Layer
"""

from django.core.management.base import BaseCommand, CommandError
from layerindex.models import LayerItem, Branch, LayerBranch

class Command(BaseCommand):
    help = 'Update or create a LayerItem with a new '

    def add_arguments(self, parser):
        parser.add_argument('--branch', action='store', dest='branch',
                            required=True, help='The LayerIndex branch this layer will be stored with.')
        parser.add_argument('--actual_branch', action='store', dest='actual_branch',
                            required=False, help='The actual branch to use for the repository')
        parser.add_argument('--name', action='store', dest='name',
                            required=True, help='The name of the Layer')
        parser.add_argument('--vcs_url', action='store', dest='vcs_url',
                            required=True, help='Where to clone the layer from')
        parser.add_argument('--vcs_subdir', action='store', dest='vcs_subdir',
                            required=False, help='Subdir of vcs_url to search for layer')

    def handle(self, *args, **options):
        branch = Branch.objects.get(name=options['branch'])

        layerItem, created = LayerItem.objects.get_or_create(name=options['name'])
        # if the layer is new, default it to published so that it can be accessed
        if created:
            layerItem.status = 'P'
            layerItem.layer_type = 'A'
            layerItem.summary = options['name']
            layerItem.description = options['name']

        layerItem.vcs_url = options['vcs_url']
        layerItem.save()

        layerBranch, created = LayerBranch.objects.get_or_create(layer=layerItem, branch=branch)
        layerBranch.actual_branch = options.get('actual_branch', options['branch'])
        vcs_subdir = options.get('vcs_subdir')
        if vcs_subdir:
            layerBranch.vcs_subdir = vcs_subdir

        layerBranch.save()
