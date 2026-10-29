"""Check native unit-test membership and the rest Live Activity Xcode graph."""
from collections import Counter
import hashlib
import json
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read_project(path):
    # OpenStep plist grammar; comments and quoted paths are tokenized before parsing.
    pattern = r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^{}()=;,\s]+'
    tokens = iter(
        match.group() for match in re.finditer(pattern, path.read_text(), re.S)
        if not match.group().startswith(('//', '/*'))
    )

    def value(token):
        if token == '{':
            result = {}
            while (key := next(tokens)) != '}':
                assert next(tokens) == '='
                assert key not in result, f'Duplicate project key: {key}'
                result[key] = value(next(tokens))
                assert next(tokens) == ';'
            return result
        if token == '(':
            result = []
            while (item := next(tokens)) != ')':
                if item != ',':
                    result.append(value(item))
            return result
        return json.loads(token) if token.startswith('"') else token

    result = value(next(tokens))
    assert next(tokens, None) is None
    return result


def check_test_source_membership(project, source_root):
    """Every native unit test must remain reachable and compile exactly once."""
    objects = project['objects']
    paths = {}

    def visit(key, parent):
        obj = objects[key]
        tree = obj.get('sourceTree', '<group>')
        if tree not in ('<group>', 'SOURCE_ROOT'):
            return
        path = (parent if tree == '<group>' else pathlib.Path('.')) / obj.get('path', '')
        if obj['isa'] == 'PBXGroup':
            for child in obj['children']:
                visit(child, path)
        elif obj['isa'] == 'PBXFileReference':
            paths[key] = path.as_posix()

    visit(objects[project['rootObject']]['mainGroup'], pathlib.Path('.'))
    target_name = 'LogYourBodyTests'
    targets = [objects[key] for key in objects[project['rootObject']]['targets']
               if objects[key]['name'] == target_name]
    assert len(targets) == 1, 'Native unit-test target must exist exactly once'
    compiled = Counter(
        paths.get(objects[item]['fileRef'])
        for phase in targets[0]['buildPhases'] if objects[phase]['isa'] == 'PBXSourcesBuildPhase'
        for item in objects[phase]['files']
    )
    expected = {path.relative_to(source_root).as_posix()
                for path in (source_root / target_name).rglob('*.swift')}
    assert expected, 'Native unit-test sources must exist'
    invalid = sorted(path for path in expected if compiled[path] != 1)
    assert not invalid, 'Native test source membership must compile exactly once: ' + ', '.join(invalid)


# Once a model version is used, keep its compiled schema reproducible. Evolve by
# adding a new version, never by resolving a merge over an existing schema.
LOCKED_MODEL_VERSIONS = {
    'LogYourBody.xcdatamodel': '1f60e718d80855eabe2fcd62b0e440459fca274cebd723669ddee89d097ccae5',
    'LogYourBodyV2.xcdatamodel': '09bcb4ccef113c8f627d99393be2a89035e7012769867123beab1beba4a6c367',
    'LogYourBodyV3.xcdatamodel': 'fb199105d312a6a6a7e725240c83b052895c9c77aa700ef089dc31d40ac38109',
    'LogYourBodyV4.xcdatamodel': '66da9882db8b7624867d6149e336f7847647c69ab1b431c7d161ef590e09db96',
    'LogYourBodyV5.xcdatamodel': 'd344e8c50e13ea843757659942ef2cadf59ad204f672026c360be25b1d6475b4',
    'LogYourBodyV6.xcdatamodel': '3ad6bfa15f2f50b936249e5bfc6caab6038f07b0b596c743c1f5624b62ed40a5',
}


def check_model_versions(project, model_root, locked=None):
    locked = LOCKED_MODEL_VERSIONS if locked is None else locked
    current = plistlib.loads((model_root / '.xccurrentversion').read_bytes())['_XCCurrentVersionName']
    versions = {path.parent.name: path for path in model_root.glob('*.xcdatamodel/contents')}
    assert set(versions) == set(locked), 'Review additive model versions; never replace a published model'
    for name, expected in locked.items():
        path = versions[name]
        assert not path.is_symlink() and not path.parent.is_symlink(), 'Model versions must be regular source files'
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, (
            'Published model version changed: ' + name + '; use an additive version')
    assert current in versions, 'Selected model version must exist'
    objects = project['objects']
    groups = [obj for obj in objects.values()
              if obj.get('isa') == 'XCVersionGroup' and obj.get('path') == model_root.name]
    assert len(groups) == 2, 'App and widget must both register the model version group'
    for group in groups:
        children = group['children']
        assert len(children) == len(set(children)), 'Duplicate model version registration'
        registered = [objects[key]['path'] for key in children]
        assert len(registered) == len(set(registered)), 'Duplicate model version paths'
        assert set(registered) == set(versions), 'Every model version must compile in app and widget'
        assert group['currentVersion'] in children, 'Current model version must be registered'
        assert objects[group['currentVersion']]['path'] == current, 'App and widget must select the current model version'


def check_project(path):
    project = read_project(path)
    check_test_source_membership(project, ROOT / 'apps/ios')
    check_model_versions(project, ROOT / 'apps/ios/LogYourBody/Models/LogYourBody.xcdatamodeld')
    objects = project['objects']
    targets = {objects[key]['name']: objects[key] for key in objects[project['rootObject']]['targets']}
    app = targets['LogYourBody']
    extension = targets['LogYourBodyRestTimer']
    assert any(objects[item]['target'] in objects[project['rootObject']]['targets'] and
               objects[objects[item]['target']]['name'] == 'LogYourBodyRestTimer'
               for item in app['dependencies']), 'App must build the extension'

    def source_refs(target):
        return {objects[item]['fileRef']
                for phase in target['buildPhases'] if objects[phase]['isa'] == 'PBXSourcesBuildPhase'
                for item in objects[phase]['files'] if 'fileRef' in objects[item]}

    app_refs = source_refs(app)
    extension_refs = source_refs(extension)
    paths = {objects[key]['path'] for key in extension_refs}
    assert paths == {'Models/TrainingRestActivityAttributes.swift', 'TrainingRestLiveActivity.swift'}
    shared = app_refs & extension_refs
    assert {objects[key]['path'] for key in shared} == {'Models/TrainingRestActivityAttributes.swift'}
    for path in ['Services/TrainingRestTimer.swift', 'Services/TrainingRestAlerts.swift', 'Views/TrainingRestTimerView.swift']:
        assert any(objects[key]['path'] == path for key in app_refs), f'Not compiled in app: {path}'
    assert any(objects[phase]['isa'] == 'PBXCopyFilesBuildPhase' and objects[phase]['dstSubfolderSpec'] == '13' and
               any(objects[item]['fileRef'] == extension['productReference'] for item in objects[phase]['files'])
               for phase in app['buildPhases']), 'App must embed the extension product'
    for configuration in objects[extension['buildConfigurationList']]['buildConfigurations']:
        settings = objects[configuration]['buildSettings']
        assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.logyourbody.app.rest-timer'
        assert settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
        assert settings['SKIP_INSTALL'] == 'YES'
    with (ROOT / 'apps/ios/LogYourBody/Info.plist').open('rb') as source:
        assert plistlib.load(source)['NSSupportsLiveActivities'] is True
    with (ROOT / 'apps/ios/LogYourBodyWidget/Info.plist').open('rb') as source:
        assert plistlib.load(source)['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'


if __name__ == '__main__':
    check_project(pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'apps/ios/LogYourBody.xcodeproj/project.pbxproj')
    print('Rest Live Activity project graph passed')
