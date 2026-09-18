"""Development-only importer. Run with a pinned orchard source checkout path.
The app ships Swift only; this script never runs at application runtime.
"""
from pathlib import Path
import re, json, sys

source = Path(sys.argv[1]) / 'swift/Sources/AppleBridge/AppleBridge.swift'
target = Path(__file__).resolve().parents[1] / 'Packages/JuliaKit/Sources/JuliaKit'
text = source.read_text()
special = {
    'Calendars': ('Calendar', 'calendar.list_calendars'),
    'Events': ('Calendar', 'calendar.list_events'),
    'Search': ('Calendar', 'calendar.search'),
    'RemindersCmd': ('Reminders', 'reminders.list'),
}
definitions, cases = [], []
for name, body in re.findall(r'struct (\w+): (?:AsyncParsableCommand|ParsableCommand) \{(.*?)(?=\nstruct |\Z)', text, re.S):
    if name in ['AppleBridge', 'Doctor']: continue
    command = re.search(r'commandName: "([^"]+)"', body)
    cmd = command[1] if command else name.lower()
    if name in special: app, tool = special[name]
    else:
        group, suffix = cmd.split('-', 1)
        app = {'mail':'Mail','reminder':'Reminders','reminders':'Reminders','file':'Files','numbers':'Numbers','pages':'Pages','keynote':'Keynote','notes':'Notes','contacts':'Contacts'}[group]
        prefix = {'reminder':'reminders','file':'files'}.get(group,group)
        tool = prefix+'.'+suffix.replace('-','_')
    description = re.search(r'abstract: ("(?:\\.|[^"\\])*")', body)[1]
    props, decls = [], []
    for annotation, attrs, prop, typ, opt, default in re.findall(r'@(Option|Argument|Flag)\((.*?)\)\s*var (\w+): (String|Int|Bool)(\?)?(?: = ([^\n]+))?', body, re.S):
        default = default.strip() if default else ''
        if tool == 'notes.search' and prop == 'searchIn': default = '"title"'
        if prop == 'maxBodyLength': default = '4000'
        if tool == 'mail.save_attachment' and prop == 'path': default = 'NSHomeDirectory() + "/Downloads"'
        help = re.search(r'help: ("(?:\\.|[^"\\])*")', attrs)[1]
        help = help.replace('0 = unlimited', 'maximum 8000')
        if tool == 'notes.search' and prop == 'searchIn': help = '"Search titles only. Read a specific note for its body."'
        required = not opt and not default
        schemaType = {'String':'string','Int':'integer','Bool':'boolean'}[typ]
        props.append(f'.init(name: "{prop}", type: .{schemaType}, required: {str(required).lower()}, help: {help})')
        getter = {'String':'string','Int':'integer','Bool':'boolean'}[typ]
        if opt: expr = f'p["{prop}"]?.{getter}'
        elif default: expr = f'p["{prop}"]?.{getter} ?? {default}'
        else: expr = f'try p.{"int" if typ=="Int" else "string"}("{prop}")'
        decls.append(f'            let {prop}: {typ}{"?" if opt else ""} = {expr}')
    run = re.search(r'func run\(\) (?:async )?throws \{(.*)\}\s*\}', body, re.S)[1].strip()
    definitions.append(f'        .init(name: "{tool}", application: "{app}", summary: {description}, parameters: [{", ".join(props)}]),')
    cases.append(f'        case "{tool}":\n'+ '\n'.join(decls) +'\n            '+run.replace('\n','\n            '))
generated = '''// Adapted from Orchard's command definitions. See ORCHARD-PROVENANCE.md.
import Foundation

extension ToolCatalog {
    static let orchard: [ToolDefinition] = [
'''+ '\n'.join(definitions)+'''
    ]
}

enum OrchardDispatch {
    static func call(_ name: String, _ p: [String: JSONValue]) async throws {
        switch name {
'''+ '\n'.join(cases)+'''
        default: throw JuliaError("Unknown tool: \\(name)")
        }
    }
}
'''
(target/'OrchardDispatch.swift').write_text(generated)
print('Imported',len(definitions),'native tools')
