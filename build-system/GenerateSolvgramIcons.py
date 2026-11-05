#!/usr/bin/env python3
"""Compile the approved settings SVGs into public CoreGraphics drawing commands.

Run from any directory. No image libraries or runtime SVG parser are needed.
The glyphs keep their SVG geometry; negative shapes become transparent cutouts.
"""
from pathlib import Path
import math
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'design/solvgram-icons/categories/round'
OUTPUT = ROOT / 'Solvgram/SolvgramMenu/Sources/SolvgramIcons.m'
NAMES = ['privacy', 'messages', 'chat-list', 'chats', 'message-menu', 'stories',
         'media', 'translation-voice', 'profiles', 'calls-notifications',
         'appearance', 'location', 'accounts', 'voice']
NS = '{http://www.w3.org/2000/svg}'


def n(value):
    value = float(value)
    return f'{value:.7f}'.rstrip('0').rstrip('.') if abs(value) > 0.00000005 else '0'


def call(name, *values):
    return f'CGPath{name}(path, NULL, ' + ', '.join(n(v) for v in values) + ');'


def arc(x, y, rx, ry, rotation, large, sweep, ex, ey):
    """SVG endpoint arc -> cubic segments, each spanning at most 90 degrees."""
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [call('AddLineToPoint', ex, ey)]
    if (x, y) == (ex, ey):
        return []
    phi = math.radians(rotation % 360)
    c, s = math.cos(phi), math.sin(phi)
    px = c * (x - ex) / 2 + s * (y - ey) / 2
    py = -s * (x - ex) / 2 + c * (y - ey) / 2
    ratio = px * px / (rx * rx) + py * py / (ry * ry)
    if ratio > 1:
        scale = math.sqrt(ratio)
        rx *= scale
        ry *= scale
    numerator = max(0, rx * rx * ry * ry - rx * rx * py * py - ry * ry * px * px)
    denominator = rx * rx * py * py + ry * ry * px * px
    factor = math.sqrt(numerator / denominator) if denominator else 0
    if bool(large) == bool(sweep):
        factor = -factor
    cxp = factor * rx * py / ry
    cyp = -factor * ry * px / rx
    cx = c * cxp - s * cyp + (x + ex) / 2
    cy = s * cxp + c * cyp + (y + ey) / 2
    start = math.atan2((py - cyp) / ry, (px - cxp) / rx)
    end = math.atan2((-py - cyp) / ry, (-px - cxp) / rx)
    delta = end - start
    if sweep and delta < 0:
        delta += 2 * math.pi
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    count = max(1, math.ceil(abs(delta) / (math.pi / 2)))
    step = delta / count

    def point(t):
        return (cx + c * rx * math.cos(t) - s * ry * math.sin(t),
                cy + s * rx * math.cos(t) + c * ry * math.sin(t))

    def tangent(t):
        return (-c * rx * math.sin(t) - s * ry * math.cos(t),
                -s * rx * math.sin(t) + c * ry * math.cos(t))

    result = []
    for i in range(count):
        a, b = start + i * step, start + (i + 1) * step
        p, q, u, v = point(a), point(b), tangent(a), tangent(b)
        k = 4 / 3 * math.tan(step / 4)
        result.append(call('AddCurveToPoint', p[0] + k * u[0], p[1] + k * u[1],
                           q[0] - k * v[0], q[1] - k * v[1],
                           ex if i == count - 1 else q[0], ey if i == count - 1 else q[1]))
    return result


def path_commands(d):
    tokens = re.findall(r'[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', d)
    result = []
    i = 0
    command = None
    x = y = sx = sy = 0
    previous = ''
    cubic = quad = (0, 0)
    sizes = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7}
    while i < len(tokens):
        if tokens[i].isalpha():
            command = tokens[i]
            i += 1
        if command.upper() == 'Z':
            result.append('CGPathCloseSubpath(path);')
            x, y = sx, sy
            previous = 'Z'
            command = None
            continue
        upper = command.upper()
        count = sizes[upper]
        values = list(map(float, tokens[i:i + count]))
        if len(values) != count:
            raise ValueError(f'Incomplete {command} in {d}')
        i += count
        relative = command.islower()

        def point(a, b):
            return (a + x, b + y) if relative else (a, b)

        if upper in ('M', 'L'):
            ex, ey = point(*values)
            result.append(call('MoveToPoint' if upper == 'M' else 'AddLineToPoint', ex, ey))
            if upper == 'M':
                sx, sy = ex, ey
                command = 'l' if relative else 'L'
        elif upper == 'H':
            ex, ey = values[0] + x if relative else values[0], y
            result.append(call('AddLineToPoint', ex, ey))
        elif upper == 'V':
            ex, ey = x, values[0] + y if relative else values[0]
            result.append(call('AddLineToPoint', ex, ey))
        elif upper in ('C', 'S'):
            if upper == 'C':
                c1 = point(*values[:2])
                c2 = point(*values[2:4])
            else:
                c1 = (2*x-cubic[0], 2*y-cubic[1]) if previous in ('C', 'S') else (x, y)
                c2 = point(*values[:2])
            ex, ey = point(*values[-2:])
            result.append(call('AddCurveToPoint', *c1, *c2, ex, ey))
            cubic = c2
        elif upper in ('Q', 'T'):
            control = point(*values[:2]) if upper == 'Q' else ((2*x-quad[0], 2*y-quad[1]) if previous in ('Q', 'T') else (x, y))
            ex, ey = point(*values[-2:])
            result.append(call('AddQuadCurveToPoint', *control, ex, ey))
            quad = control
        elif upper == 'A':
            ex, ey = point(*values[-2:])
            result.extend(arc(x, y, *values[:5], ex, ey))
        x, y = ex, ey
        previous = upper
    return result


def shape(element):
    a = element.attrib
    tag = element.tag.removeprefix(NS)
    if tag == 'path':
        return path_commands(a['d'])
    if tag in ('circle', 'ellipse'):
        rx = float(a.get('r', a.get('rx', 0)))
        ry = float(a.get('r', a.get('ry', 0)))
        x, y = float(a['cx']) - rx, float(a['cy']) - ry
        return [f'CGPathAddEllipseInRect(path, NULL, CGRectMake({n(x)}, {n(y)}, {n(2*rx)}, {n(2*ry)}));']
    if tag == 'rect':
        x, y, w, h = [float(a.get(key, 0)) for key in ('x', 'y', 'width', 'height')]
        rx = float(a.get('rx', a.get('ry', 0)))
        ry = float(a.get('ry', a.get('rx', 0)))
        rect = f'CGRectMake({n(x)}, {n(y)}, {n(w)}, {n(h)})'
        return [f'CGPathAddRoundedRect(path, NULL, {rect}, {n(rx)}, {n(ry)});'] if rx or ry else [f'CGPathAddRect(path, NULL, {rect});']
    raise ValueError(f'Unsupported SVG shape: {tag}')


def drawing(root):
    result = ['CGMutablePathRef path;']
    masks = {el.attrib['id']: el for el in root.iter(NS + 'mask')}

    def walk(element, inherited):
        tag = element.tag.removeprefix(NS)
        if tag in ('defs', 'title'):
            return
        style = dict(inherited)
        style.update(element.attrib)
        style['opacity'] = float(inherited.get('opacity', 1)) * float(element.attrib.get('opacity', 1))
        result.append('CGContextSaveGState(context);')
        for transform, arguments in re.findall(r'(\w+)\(([^)]*)\)', element.attrib.get('transform', '')):
            v = list(map(float, re.findall(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)', arguments)))
            if transform == 'translate':
                result.append(f'CGContextTranslateCTM(context, {n(v[0])}, {n(v[1] if len(v)>1 else 0)});')
            elif transform == 'scale':
                result.append(f'CGContextScaleCTM(context, {n(v[0])}, {n(v[1] if len(v)>1 else v[0])});')
            else:
                raise ValueError(f'Unsupported SVG transform: {transform}')
        if tag == 'g':
            for child in element:
                walk(child, style)
        else:
            if 'mask' in element.attrib:
                mask = masks[re.search(r'#([^)]*)', element.attrib['mask'])[1]]
                # Mask cuts only this element, not the foreground badge.
                result.append('CGContextBeginPath(context);')
                for mask_shape in mask:
                    if mask_shape.attrib.get('fill') == 'white':
                        continue
                    if mask_shape.tag == NS + 'circle':
                        m = mask_shape.attrib
                        r = float(m['r'])
                        result.append('CGContextAddEllipseInRect(context, CGRectMake(' + ', '.join(n(v) for v in (float(m['cx'])-r, float(m['cy'])-r, 2*r, 2*r)) + '));')
                    else:
                        raise ValueError('Unsupported mask cutout')
                result.append('CGContextAddRect(context, CGRectMake(0, 0, 24, 24));')
                result.append('CGContextEOClip(context);')
            result.append('path = CGPathCreateMutable();')
            result.extend(shape(element))
            result.append(f'CGContextSetAlpha(context, {n(style["opacity"])});')
            fill = style.get('fill', 'white')
            stroke = style.get('stroke', 'none')
            if fill != 'none':
                if fill != 'white' and not fill.startswith('url('):
                    raise ValueError(f'Unsupported fill: {fill}')
                result.append(f'CGContextSetBlendMode(context, {"kCGBlendModeClear" if fill.startswith("url(") else "kCGBlendModeNormal"});')
                result.append('CGContextSetRGBFillColor(context, 1, 1, 1, 1);')
                result.append('CGContextAddPath(context, path);')
                result.append('CGContextEOFillPath(context);' if style.get('fill-rule') == 'evenodd' else 'CGContextFillPath(context);')
            if stroke != 'none':
                if stroke != 'white' and not stroke.startswith('url('):
                    raise ValueError(f'Unsupported stroke: {stroke}')
                result.append(f'CGContextSetBlendMode(context, {"kCGBlendModeClear" if stroke.startswith("url(") else "kCGBlendModeNormal"});')
                result.append('CGContextSetRGBStrokeColor(context, 1, 1, 1, 1);')
                result.append(f'CGContextSetLineWidth(context, {style.get("stroke-width", "1")});')
                caps = {'round':'kCGLineCapRound','butt':'kCGLineCapButt','square':'kCGLineCapSquare'}
                joins = {'round':'kCGLineJoinRound','miter':'kCGLineJoinMiter','bevel':'kCGLineJoinBevel'}
                result.append(f'CGContextSetLineCap(context, {caps[style.get("stroke-linecap", "butt")]});')
                result.append(f'CGContextSetLineJoin(context, {joins[style.get("stroke-linejoin", "miter")]});')
                result.append('CGContextAddPath(context, path);')
                result.append('CGContextStrokePath(context);')
            result.append('CGPathRelease(path);')
        result.append('CGContextRestoreGState(context);')

    for child in root.findall(NS+'g'):
        walk(child, {'fill':'white'})
    return result


def swift_commands(commands):
    result = []
    def point(x, y): return f'CGPoint(x: {x}, y: {y})'
    def arguments(value):
        values, start, depth = [], 0, 0
        for i, char in enumerate(value):
            if char == '(': depth += 1
            elif char == ')': depth -= 1
            elif char == ',' and depth == 0:
                values.append(value[start:i].strip()); start = i + 1
        return values + [value[start:].strip()]
    def rect(value):
        v = arguments(value.removeprefix('CGRectMake(').removesuffix(')'))
        return f'CGRect(x: {v[0]}, y: {v[1]}, width: {v[2]}, height: {v[3]})'
    for line in commands:
        if line == 'CGMutablePathRef path;': result.append('var path: CGMutablePath!'); continue
        if line == 'path = CGPathCreateMutable();': result.append('path = CGMutablePath()'); continue
        if line == 'CGPathRelease(path);': continue
        m = re.fullmatch(r'(\w+)\((.*)\);', line)
        name, a = m[1], arguments(m[2])
        if name == 'CGPathMoveToPoint': value = 'path.move(to: ' + point(*a[2:]) + ')'
        elif name == 'CGPathAddLineToPoint': value = 'path.addLine(to: ' + point(*a[2:]) + ')'
        elif name == 'CGPathAddCurveToPoint': value = f'path.addCurve(to: {point(*a[6:8])}, control1: {point(*a[2:4])}, control2: {point(*a[4:6])})'
        elif name == 'CGPathAddQuadCurveToPoint': value = f'path.addQuadCurve(to: {point(*a[4:6])}, control: {point(*a[2:4])})'
        elif name == 'CGPathCloseSubpath': value = 'path.closeSubpath()'
        elif name == 'CGPathAddEllipseInRect': value = f'path.addEllipse(in: {rect(a[2])})'
        elif name == 'CGPathAddRect': value = f'path.addRect({rect(a[2])})'
        elif name == 'CGPathAddRoundedRect': value = f'path.addRoundedRect(in: {rect(a[2])}, cornerWidth: {a[3]}, cornerHeight: {a[4]})'
        elif name == 'CGContextSaveGState': value = 'context.saveGState()'
        elif name == 'CGContextRestoreGState': value = 'context.restoreGState()'
        elif name == 'CGContextTranslateCTM': value = f'context.translateBy(x: {a[1]}, y: {a[2]})'
        elif name == 'CGContextScaleCTM': value = f'context.scaleBy(x: {a[1]}, y: {a[2]})'
        elif name == 'CGContextBeginPath': value = 'context.beginPath()'
        elif name == 'CGContextAddEllipseInRect': value = f'context.addEllipse(in: {rect(a[1])})'
        elif name == 'CGContextAddRect': value = f'context.addRect({rect(a[1])})'
        elif name == 'CGContextEOClip': value = 'context.clip(using: .evenOdd)'
        elif name == 'CGContextSetAlpha': value = f'context.setAlpha({a[1]})'
        elif name == 'CGContextSetBlendMode': value = 'context.setBlendMode(.' + ('clear' if a[1]=='kCGBlendModeClear' else 'normal') + ')'
        elif name == 'CGContextSetRGBFillColor': value = 'context.setFillColor(UIColor.white.cgColor)'
        elif name == 'CGContextSetRGBStrokeColor': value = 'context.setStrokeColor(UIColor.white.cgColor)'
        elif name == 'CGContextAddPath': value = 'context.addPath(path)'
        elif name == 'CGContextFillPath': value = 'context.fillPath()'
        elif name == 'CGContextEOFillPath': value = 'context.fillPath(using: .evenOdd)'
        elif name == 'CGContextStrokePath': value = 'context.strokePath()'
        elif name == 'CGContextSetLineWidth': value = f'context.setLineWidth({a[1]})'
        elif name == 'CGContextSetLineCap': value = 'context.setLineCap(.' + a[1].removeprefix('kCGLineCap').lower() + ')'
        elif name == 'CGContextSetLineJoin': value = 'context.setLineJoin(.' + a[1].removeprefix('kCGLineJoin').lower() + ')'
        else: raise ValueError(f'Unsupported Swift conversion: {line}')
        result.append(value)
    return result


def generate_swift(sources):
    out = ['// Generated by build-system/GenerateSolvgramIcons.py.',
           '// MARK: Solvgram — vector artwork used by the live Swift settings screen.',
           'import UIKit', 'import SolvgramIcons', '', 'enum SolvgramSettingsIcons {',
           '    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]', '']
    specs = []
    for name, source in sources:
        root = ET.parse(source).getroot()
        stops = list(root.iter(NS+'stop'))
        colors = []
        for stop in stops[:2]:
            rgb = stop.attrib['stop-color'].lstrip('#')
            colors.append('UIColor(red: '+n(int(rgb[:2],16)/255)+', green: '+n(int(rgb[2:4],16)/255)+', blue: '+n(int(rgb[4:6],16)/255)+', alpha: 1).cgColor')
        func = 'draw_' + name.replace('-', '_')
        out += [f'    private static func {func}(_ context: CGContext) {{']
        if name == 'ghost':
            out += ['        context.saveGState()',
                    '        context.translateBy(x: 5, y: 5)',
                    '        context.scaleBy(x: 0.91667, y: 0.91667)',
                    '        SolvgramGhostIcon.draw(in: context, color: .white)',
                    '        context.restoreGState()']
        else:
            out += ['        '+line for line in swift_commands(drawing(root))]
        out += ['    }', '']
        specs.append((name, func, colors))
    out += ['    static func image(named name: String, side: CGFloat = 30) -> UIImage? {',
            '        guard side > 0 else { return nil }',
            '        let key = "\\(name)|\\(side)"',
            '        if let image = cache[key] { return image }',
            '        let colors: [CGColor]', '        let draw: (CGContext) -> Void',
            '        switch name {']
    out += ['        case "app-badge":', '            colors = [UIColor(red: 1, green: 0.48, blue: 0.66, alpha: 1).cgColor, UIColor.systemPink.cgColor]', '            draw = SolvgramBadgeArtwork.drawSettingsIcon']
    for name, func, colors in specs:
        out += [f'        case "{name}":',f'            colors = [{colors[0]}, {colors[1]}]',f'            draw = {func}']
    out += ['        default: return nil', '        }',
'''        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { renderer in
            let context = renderer.cgContext
            context.scaleBy(x: side / 32, y: side / 32)
            context.saveGState()
            context.addEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 32))
            context.clip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 32), options: [])
            }
            context.restoreGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            draw(context)
            context.endTransparencyLayer()
        }
        cache[key] = image
        return image
    }
}''']
    (ROOT/'Solvgram/SGSettingsUI/Sources/SolvgramSettingsIcons.swift').write_text('\n'.join(out)+'\n')


def main():
    sources = [(name, SOURCES/(name+'.svg')) for name in NAMES]
    sources.append(('ghost', ROOT/'design/solvgram-icons/v8/ghost.svg'))
    out = ['// Generated by build-system/GenerateSolvgramIcons.py. Edit the approved SVGs, then regenerate.',
           '// MARK: Solvgram — custom, resolution-independent settings icons.',
           '#import "SolvgramIcons.h"', '']
    specs = []
    for name, source in sources:
        root = ET.parse(source).getroot()
        stops = list(root.iter(NS+'stop'))
        colors = []
        for stop in stops[:2]:
            color = stop.attrib['stop-color'].lstrip('#')
            colors.append(', '.join(n(int(color[i:i+2],16)/255) for i in (0,2,4)))
        function = 'SGDraw_' + name.replace('-', '_')
        out += [f'static void {function}(CGContextRef context) {{']
        out += ['    '+line for line in drawing(root)]
        out += ['}', '']
        specs.append(f'    {{ "{name}", {{ {colors[0]} }}, {{ {colors[1]} }}, {function} }},')
    out += ['typedef struct {', '    const char *name;', '    CGFloat top[3];', '    CGFloat bottom[3];',
            '    void (*draw)(CGContextRef);', '} SGIconSpec;', '', 'static const SGIconSpec SGIcons[] = {', *specs, '};', '',
'''UIImage *SolvgramMenuIcon(NSString *name, CGFloat side) {
    if (name.length == 0 || side <= 0) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%@|%g", name, (double)side];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    const SGIconSpec *spec = NULL;
    for (NSUInteger i = 0; i < sizeof(SGIcons) / sizeof(SGIcons[0]); i++) {
        if ([name isEqualToString:[NSString stringWithUTF8String:SGIcons[i].name]]) {
            spec = &SGIcons[i];
            break;
        }
    }
    if (!spec) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef cg = context.CGContext;
        CGContextScaleCTM(cg, side / 32.0, side / 32.0);
        CGContextSaveGState(cg);
        CGContextAddEllipseInRect(cg, CGRectMake(0, 0, 32, 32));
        CGContextClip(cg);
        CGFloat colors[] = { spec->top[0], spec->top[1], spec->top[2], 1,
                             spec->bottom[0], spec->bottom[1], spec->bottom[2], 1 };
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
        CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(0, 32), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        CGContextRestoreGState(cg);
        // Isolate cutouts from the colored background; the SVG's negative shapes stay transparent.
        CGContextBeginTransparencyLayer(cg, NULL);
        spec->draw(cg);
        CGContextEndTransparencyLayer(cg);
    }];
    [cache setObject:image forKey:key];
    return image;
}''']
    OUTPUT.write_text('\n'.join(out)+'\n')
    generate_swift(sources)
    print(f'Generated {len(sources)} vector icons: {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
