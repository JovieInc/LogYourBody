"""Check native unit-test membership and the rest Live Activity Xcode graph."""
from collections import Counter
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


def check_project(path):
    project = read_project(path)
    check_test_source_membership(project, ROOT / 'apps/ios')
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
