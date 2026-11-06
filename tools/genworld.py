#!/usr/bin/env python3
"""Makes src/retroui/worlddata.nim, the countries of retro's map view, from the
Natural Earth 1:50m admin-0 countries as the npm package `world-atlas`
(2.x) has them (countries-50m.json, TopoJSON).

  npm pack world-atlas@2 && tar xzf world-atlas-*.tgz
  pip install pycountry
  python3 tools/genworld.py package/countries-50m.json

The shared borders are simplified once (Douglas-Peucker), so neighbours
still meet; rings are stored as 1/100 degree steps, zigzag varints.

Natural Earth is in the public domain; world-atlas is (c) Mike Bostock,
ISC licence (see src/retroui/fonts/LICENSE-NaturalEarth.txt).
"""
import json, math, os, sys

TOLERANCE = 0.06        # degrees: what simplifying may move a border by
MIN_AREA = 0.02         # square degrees: smaller islands are dropped (not
                        # a country's largest piece)
SCALE = 100             # stored in 1/100 degree

# shorter names for the ones Natural Earth abbreviates or pycountry spells
# officially
NAMES = {
    'BO': 'Bolivia', 'BN': 'Brunei', 'CD': 'DR Congo', 'CG': 'Congo',
    'CI': "Cote d'Ivoire", 'CZ': 'Czechia', 'FK': 'Falkland Islands',
    'FM': 'Micronesia', 'GB': 'United Kingdom', 'IR': 'Iran', 'KP': 'North Korea',
    'KR': 'South Korea', 'LA': 'Laos', 'MD': 'Moldova', 'MK': 'North Macedonia',
    'PS': 'Palestine', 'RU': 'Russia', 'SY': 'Syria', 'TW': 'Taiwan',
    'TZ': 'Tanzania', 'US': 'United States', 'VE': 'Venezuela', 'VN': 'Vietnam',
    'VA': 'Vatican', 'BA': 'Bosnia and Herzegovina', 'CF': 'Central African Republic',
    'DO': 'Dominican Republic', 'GQ': 'Equatorial Guinea', 'SS': 'South Sudan',
    'SB': 'Solomon Islands', 'EH': 'Western Sahara', 'TF': 'French Southern Lands',
    'SZ': 'Eswatini', 'TL': 'Timor-Leste', 'CV': 'Cabo Verde', 'KN': 'Saint Kitts and Nevis',
    'VC': 'Saint Vincent and the Grenadines', 'LC': 'Saint Lucia',
    'VG': 'British Virgin Islands', 'VI': 'U.S. Virgin Islands',
    'HM': 'Heard and McDonald Islands', 'SH': 'Saint Helena',
    'GS': 'South Georgia', 'IO': 'British Indian Ocean Territory',
    'PN': 'Pitcairn Islands', 'MP': 'Northern Mariana Islands',
    'TC': 'Turks and Caicos', 'WF': 'Wallis and Futuna', 'PM': 'Saint Pierre and Miquelon',
    'MF': 'Saint Martin', 'SX': 'Sint Maarten', 'BL': 'Saint Barthelemy',
    'AG': 'Antigua and Barbuda', 'ST': 'Sao Tome and Principe', 'CW': 'Curacao',
    'AX': 'Aland Islands', 'RE': 'Reunion', 'KY': 'Cayman Islands',
}
# features without an ISO number
EXTRA = {
    'Kosovo': ('XK', 'XKX', 'Kosovo'),
    'N. Cyprus': ('', '', 'Northern Cyprus'),
    'Somaliland': ('', '', 'Somaliland'),
    'Indian Ocean Ter.': ('', '', 'Indian Ocean Territories'),
    'Siachen Glacier': ('', '', 'Siachen Glacier'),
}

# cities for markers by name: (name, country alpha-2, lat, lon)
CITIES = [
    ('Muscat', 'OM', 23.59, 58.41), ('Sohar', 'OM', 24.35, 56.71),
    ('Salalah', 'OM', 17.02, 54.09), ('Nizwa', 'OM', 22.93, 57.53),
    ('Sur', 'OM', 22.57, 59.53), ('Duqm', 'OM', 19.66, 57.70),
    ('Dubai', 'AE', 25.20, 55.27), ('Abu Dhabi', 'AE', 24.45, 54.38),
    ('Sharjah', 'AE', 25.35, 55.40), ('Doha', 'QA', 25.29, 51.53),
    ('Manama', 'BH', 26.23, 50.59), ('Kuwait City', 'KW', 29.38, 47.99),
    ('Riyadh', 'SA', 24.71, 46.68), ('Jeddah', 'SA', 21.49, 39.19),
    ('Mecca', 'SA', 21.39, 39.86), ('Medina', 'SA', 24.47, 39.61),
    ('Dammam', 'SA', 26.43, 50.10), ("Sana'a", 'YE', 15.37, 44.19),
    ('Aden', 'YE', 12.79, 45.02), ('Baghdad', 'IQ', 33.31, 44.36),
    ('Tehran', 'IR', 35.69, 51.39), ('Amman', 'JO', 31.95, 35.93),
    ('Beirut', 'LB', 33.89, 35.50), ('Damascus', 'SY', 33.51, 36.28),
    ('Jerusalem', 'IL', 31.77, 35.21), ('Cairo', 'EG', 30.04, 31.24),
    ('Alexandria', 'EG', 31.20, 29.92), ('Istanbul', 'TR', 41.01, 28.98),
    ('Ankara', 'TR', 39.93, 32.86), ('Karachi', 'PK', 24.86, 67.01),
    ('Islamabad', 'PK', 33.68, 73.05), ('Lahore', 'PK', 31.55, 74.34),
    ('Kabul', 'AF', 34.56, 69.21), ('New Delhi', 'IN', 28.61, 77.21),
    ('Mumbai', 'IN', 19.08, 72.88), ('Bengaluru', 'IN', 12.97, 77.59),
    ('Chennai', 'IN', 13.08, 80.27), ('Kolkata', 'IN', 22.57, 88.36),
    ('Hyderabad', 'IN', 17.39, 78.49), ('Kochi', 'IN', 9.93, 76.27),
    ('Dhaka', 'BD', 23.81, 90.41), ('Colombo', 'LK', 6.93, 79.86),
    ('Kathmandu', 'NP', 27.72, 85.32), ('Male', 'MV', 4.18, 73.51),
    ('Beijing', 'CN', 39.90, 116.41), ('Shanghai', 'CN', 31.23, 121.47),
    ('Shenzhen', 'CN', 22.54, 114.06), ('Guangzhou', 'CN', 23.13, 113.26),
    ('Hong Kong', 'HK', 22.32, 114.17), ('Taipei', 'TW', 25.03, 121.57),
    ('Tokyo', 'JP', 35.68, 139.69), ('Osaka', 'JP', 34.69, 135.50),
    ('Seoul', 'KR', 37.57, 126.98), ('Manila', 'PH', 14.60, 120.98),
    ('Bangkok', 'TH', 13.76, 100.50), ('Hanoi', 'VN', 21.03, 105.85),
    ('Ho Chi Minh City', 'VN', 10.82, 106.63), ('Kuala Lumpur', 'MY', 3.14, 101.69),
    ('Singapore', 'SG', 1.35, 103.82), ('Jakarta', 'ID', -6.21, 106.85),
    ('Sydney', 'AU', -33.87, 151.21), ('Melbourne', 'AU', -37.81, 144.96),
    ('Perth', 'AU', -31.95, 115.86), ('Brisbane', 'AU', -27.47, 153.03),
    ('Canberra', 'AU', -35.28, 149.13), ('Auckland', 'NZ', -36.85, 174.76),
    ('Wellington', 'NZ', -41.29, 174.78), ('Moscow', 'RU', 55.76, 37.62),
    ('Saint Petersburg', 'RU', 59.93, 30.36), ('Kyiv', 'UA', 50.45, 30.52),
    ('Warsaw', 'PL', 52.23, 21.01), ('Berlin', 'DE', 52.52, 13.40),
    ('Frankfurt', 'DE', 50.11, 8.68), ('Munich', 'DE', 48.14, 11.58),
    ('Hamburg', 'DE', 53.55, 9.99), ('Paris', 'FR', 48.86, 2.35),
    ('Lyon', 'FR', 45.76, 4.84), ('Marseille', 'FR', 43.30, 5.37),
    ('London', 'GB', 51.51, -0.13), ('Manchester', 'GB', 53.48, -2.24),
    ('Edinburgh', 'GB', 55.95, -3.19), ('Dublin', 'IE', 53.35, -6.26),
    ('Madrid', 'ES', 40.42, -3.70), ('Barcelona', 'ES', 41.39, 2.17),
    ('Lisbon', 'PT', 38.72, -9.14), ('Rome', 'IT', 41.90, 12.50),
    ('Milan', 'IT', 45.46, 9.19), ('Vienna', 'AT', 48.21, 16.37),
    ('Zurich', 'CH', 47.38, 8.54), ('Geneva', 'CH', 46.20, 6.14),
    ('Brussels', 'BE', 50.85, 4.35), ('Amsterdam', 'NL', 52.37, 4.90),
    ('Copenhagen', 'DK', 55.68, 12.57), ('Stockholm', 'SE', 59.33, 18.07),
    ('Oslo', 'NO', 59.91, 10.75), ('Helsinki', 'FI', 60.17, 24.94),
    ('Prague', 'CZ', 50.08, 14.44), ('Budapest', 'HU', 47.50, 19.04),
    ('Bucharest', 'RO', 44.43, 26.10), ('Athens', 'GR', 37.98, 23.73),
    ('Casablanca', 'MA', 33.57, -7.59), ('Rabat', 'MA', 34.02, -6.84),
    ('Algiers', 'DZ', 36.75, 3.06), ('Tunis', 'TN', 36.81, 10.18),
    ('Tripoli', 'LY', 32.89, 13.19), ('Khartoum', 'SD', 15.50, 32.56),
    ('Addis Ababa', 'ET', 9.03, 38.74), ('Nairobi', 'KE', -1.29, 36.82),
    ('Mombasa', 'KE', -4.04, 39.67), ('Dar es Salaam', 'TZ', -6.79, 39.21),
    ('Zanzibar', 'TZ', -6.17, 39.20), ('Kampala', 'UG', 0.35, 32.58),
    ('Kigali', 'RW', -1.95, 30.06), ('Mogadishu', 'SO', 2.05, 45.32),
    ('Djibouti', 'DJ', 11.59, 43.15), ('Lagos', 'NG', 6.52, 3.38),
    ('Abuja', 'NG', 9.08, 7.40), ('Accra', 'GH', 5.60, -0.19),
    ('Dakar', 'SN', 14.72, -17.47), ('Kinshasa', 'CD', -4.44, 15.27),
    ('Luanda', 'AO', -8.84, 13.23), ('Johannesburg', 'ZA', -26.20, 28.05),
    ('Cape Town', 'ZA', -33.92, 18.42), ('Durban', 'ZA', -29.86, 31.02),
    ('Harare', 'ZW', -17.83, 31.05), ('Maputo', 'MZ', -25.97, 32.57),
    ('Antananarivo', 'MG', -18.88, 47.51), ('New York', 'US', 40.71, -74.01),
    ('Washington', 'US', 38.91, -77.04), ('Chicago', 'US', 41.88, -87.63),
    ('Los Angeles', 'US', 34.05, -118.24), ('San Francisco', 'US', 37.77, -122.42),
    ('Seattle', 'US', 47.61, -122.33), ('Houston', 'US', 29.76, -95.37),
    ('Dallas', 'US', 32.78, -96.80), ('Miami', 'US', 25.76, -80.19),
    ('Atlanta', 'US', 33.75, -84.39), ('Boston', 'US', 42.36, -71.06),
    ('Toronto', 'CA', 43.65, -79.38), ('Montreal', 'CA', 45.50, -73.57),
    ('Vancouver', 'CA', 49.28, -123.12), ('Ottawa', 'CA', 45.42, -75.70),
    ('Mexico City', 'MX', 19.43, -99.13), ('Havana', 'CU', 23.11, -82.37),
    ('Panama City', 'PA', 8.98, -79.52), ('Bogota', 'CO', 4.71, -74.07),
    ('Lima', 'PE', -12.05, -77.04), ('Quito', 'EC', -0.18, -78.47),
    ('Caracas', 'VE', 10.48, -66.90), ('Santiago', 'CL', -33.45, -70.67),
    ('Buenos Aires', 'AR', -34.60, -58.38), ('Montevideo', 'UY', -34.90, -56.16),
    ('Sao Paulo', 'BR', -23.55, -46.63), ('Rio de Janeiro', 'BR', -22.91, -43.17),
    ('Brasilia', 'BR', -15.79, -47.88), ('Reykjavik', 'IS', 64.15, -21.94),
    ('Tashkent', 'UZ', 41.30, 69.24), ('Almaty', 'KZ', 43.24, 76.89),
    ('Baku', 'AZ', 40.41, 49.87), ('Tbilisi', 'GE', 41.72, 44.79),
    ('Yerevan', 'AM', 40.18, 44.51), ('Ulaanbaatar', 'MN', 47.89, 106.91),
]


def decode_arcs(topo):
    sx, sy = topo['transform']['scale']
    tx, ty = topo['transform']['translate']
    arcs = []
    for arc in topo['arcs']:
        x = y = 0
        pts = []
        for dx, dy in arc:
            x += dx
            y += dy
            pts.append((x * sx + tx, y * sy + ty))
        arcs.append(pts)
    return arcs


def dp(pts, tol):
    """Douglas-Peucker, keeping both ends."""
    if len(pts) < 3:
        return pts[:]
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        ll = math.hypot(dx, dy)
        best, at = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if ll == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / ll
            if d > best:
                best, at = d, i
        if best > tol and at > 0:
            keep[at] = True
            stack.append((a, at))
            stack.append((at, b))
    return [p for p, k in zip(pts, keep) if k]


def simplify(arc, tol):
    if len(arc) > 3 and arc[0] == arc[-1]:
        # a closed arc: split at the point farthest from its start
        far = max(range(len(arc)), key=lambda i: math.hypot(arc[i][0] - arc[0][0],
                                                            arc[i][1] - arc[0][1]))
        a = dp(arc[:far + 1], tol)
        b = dp(arc[far:], tol)
        return a + b[1:]
    return dp(arc, tol)


def ring_of(idx, arcs):
    out = []
    for i in idx:
        a = arcs[i] if i >= 0 else list(reversed(arcs[~i]))
        if out:
            a = a[1:]
        out.extend(a)
    return out


def split_ring(r):
    """A ring that crosses the date line, as rings on each side of it,
    closed along the line (the data puts its points on +-180 there). A
    ring around a pole (it crosses once) goes round by the pole."""
    jumps = [i for i in range(len(r)) if abs(r[i][0] - r[i - 1][0]) > 180]
    if not jumps:
        return [r]
    if len(jumps) % 2 == 1:
        i = jumps[0]
        pole = -90.0 if sum(p[1] for p in r) < 0 else 90.0
        a, b = r[i - 1], r[i]
        return [r[:i] + [(a[0], pole), (b[0], pole)] + r[i:]]
    # pieces between the crossings; each closes along the line
    pieces = []
    for k, i in enumerate(jumps):
        j = jumps[(k + 1) % len(jumps)]
        piece = r[i:j] if i < j else r[i:] + r[:j]
        if len(piece) >= 3:
            pieces.append(piece)
    return pieces


def area(r):
    s = 0.0
    for i in range(len(r)):
        x1, y1 = r[i]
        x2, y2 = r[(i + 1) % len(r)]
        s += x1 * y2 - x2 * y1
    return s / 2


def centroid(r):
    a = area(r)
    if abs(a) < 1e-12:
        xs = [p[0] for p in r]
        ys = [p[1] for p in r]
        return (sum(xs) / len(xs), sum(ys) / len(ys))
    cx = cy = 0.0
    for i in range(len(r)):
        x1, y1 = r[i]
        x2, y2 = r[(i + 1) % len(r)]
        f = x1 * y2 - x2 * y1
        cx += (x1 + x2) * f
        cy += (y1 + y2) * f
    return (cx / (6 * a), cy / (6 * a))


def inside(r, x, y):
    c = False
    j = len(r) - 1
    for i in range(len(r)):
        xi, yi = r[i]
        xj, yj = r[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def label_point(r):
    cx, cy = centroid(r)
    if inside(r, cx, cy):
        return cx, cy
    # the middle of the widest span across the ring at the centroid's height
    xs = []
    j = len(r) - 1
    for i in range(len(r)):
        (x1, y1), (x2, y2) = r[i], r[j]
        if (y1 > cy) != (y2 > cy):
            xs.append(x1 + (cy - y1) * (x2 - x1) / (y2 - y1))
        j = i
    xs.sort()
    best = None
    for k in range(0, len(xs) - 1, 2):
        if best is None or xs[k + 1] - xs[k] > best[1] - best[0]:
            best = (xs[k], xs[k + 1])
    if best:
        return ((best[0] + best[1]) / 2, cy)
    return r[0]


def zz(v):
    return (v << 1) ^ (v >> 63)


def varint(v, out):
    v = zz(v)
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)


def main(path):
    import pycountry
    topo = json.load(open(path))
    raw = decode_arcs(topo)
    # each border is simplified once, at most by an eighth of the smallest
    # country it bounds: small countries (Bahrain, Monaco) keep their shape
    def arc_ids(g):
        polys = g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']] if g['type'] == 'Polygon' else []
        for poly in polys:
            for ring in poly:
                for i in ring:
                    yield i if i >= 0 else ~i
    tol = [TOLERANCE] * len(raw)
    for g in topo['objects']['countries']['geometries']:
        ids = list(arc_ids(g))
        if not ids:
            continue
        xs = [p[0] for i in ids for p in raw[i]]
        ys = [p[1] for i in ids for p in raw[i]]
        size = max(max(xs) - min(xs), max(ys) - min(ys))
        for i in ids:
            tol[i] = min(tol[i], max(0.005, size / 8))
    arcs = [simplify(a, tol[i]) for i, a in enumerate(raw)]
    countries = []
    dropped = []
    for g in topo['objects']['countries']['geometries']:
        name = g['properties']['name']
        polys = g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']] if g['type'] == 'Polygon' else []
        rings = []
        allpts = []
        for poly in polys:
            for k, ringIdx in enumerate(poly):
                whole = ring_of(ringIdx, arcs)
                allpts.extend(whole)
                for r in split_ring(whole):
                    q = []
                    for x, y in r:
                        p = (int(round(x * SCALE)), int(round(y * SCALE)))
                        if not q or q[-1] != p:
                            q.append(p)
                    if len(q) > 1 and q[0] == q[-1]:
                        q.pop()
                    if len(q) >= 3:
                        rings.append(q)
        if not rings and allpts:
            # islands smaller than a step (atolls): a small diamond where
            # they are, so the country can still be seen and picked
            cx = int(round(sum(p[0] for p in allpts) / len(allpts) * SCALE))
            cy = int(round(sum(p[1] for p in allpts) / len(allpts) * SCALE))
            d = 8
            rings = [[(cx, cy - d), (cx + d, cy), (cx, cy + d), (cx - d, cy)]]
        if not rings:
            dropped.append(name)
            continue
        areas = [abs(area(r)) / SCALE / SCALE for r in rings]
        big = max(range(len(rings)), key=lambda i: areas[i])
        rings = [r for i, r in enumerate(rings) if i == big or areas[i] >= MIN_AREA]
        rings.sort(key=lambda r: -abs(area(r)))
        if 'id' in g:
            c = pycountry.countries.get(numeric=g['id'])
            if c is None:
                a2, a3, nm = '', '', name
            else:
                a2, a3 = c.alpha_2, c.alpha_3
                nm = NAMES.get(a2) or getattr(c, 'common_name', None) or c.name
                if ',' in nm or len(nm) > 32:
                    nm = name
            num = int(g['id'])
        else:
            a2, a3, nm = EXTRA.get(name, ('', '', name))
            num = 0
        lx, ly = label_point([(x / SCALE, y / SCALE) for x, y in rings[0]])
        xs = [p[0] for r in rings for p in r]
        ys = [p[1] for r in rings for p in r]
        countries.append(dict(name=nm, a2=a2, a3=a3, num=num, rings=rings,
                              box=(min(xs), min(ys), max(xs), max(ys)),
                              label=(int(round(lx * SCALE)), int(round(ly * SCALE))),
                              area=sum(abs(area(r)) for r in rings)))
    # large ones first: enclaves (Lesotho, San Marino) are drawn over the
    # country around them
    countries.sort(key=lambda c: -c['area'])
    blob = bytearray()
    ring_off, ring_start = [], []
    for c in countries:
        ring_start.append(len(ring_off))
        for r in c['rings']:
            ring_off.append(len(blob))
            varint(len(r), blob)
            px = py = 0
            for x, y in r:
                varint(x - px, blob)
                varint(y - py, blob)
                px, py = x, y
    ring_start.append(len(ring_off))
    ring_off.append(len(blob))
    npts = sum(len(r) for c in countries for r in c['rings'])

    def nimstr(b):
        return '"' + ''.join('\\x%02x' % x for x in b) + '"'

    def arr(name, typ, vals, per=16):
        lines = []
        for i in range(0, len(vals), per):
            lines.append('    ' + ', '.join(str(v) for v in vals[i:i + per]) + ',')
        suffix = {'uint16': "'u16", 'int16': "'i16", 'uint32': "'u32"}[typ]
        if lines:
            lines[0] = lines[0].replace(str(vals[0]), '%s%s' % (vals[0], suffix), 1)
        return ['  %s*: array[%d, %s] = [' % (name, len(vals), typ)] + lines + ['  ]']

    out = ['## The countries of the world for retro\'s map view: Natural Earth 1:50m',
           '## admin-0 (public domain) as world-atlas has them (ISC, (c) Mike',
           '## Bostock), simplified. Generated by tools/genworld.py -- do not edit.',
           '##',
           '## Points are 1/100 degree (lon, lat), zigzag varints: per ring its',
           '## point count, then the steps from the point before (from 0, 0).',
           '',
           'const',
           '  WorldCount* = %d' % len(countries),
           '  WorldRings* = %d' % len(ring_off[:-1]),
           '  WorldScale* = %d' % SCALE,
           '  worldNames*: array[%d, string] = [' % len(countries)]
    for c in countries:
        out.append('    %s,' % json.dumps(c['name']))
    out.append('  ]')
    out.append('  worldA2* = %s' % json.dumps(''.join((c['a2'] or '--') for c in countries)))
    out.append('  worldA3* = %s' % json.dumps(''.join((c['a3'] or '---') for c in countries)))
    out += arr('worldNum', 'uint16', [c['num'] for c in countries])
    out += arr('worldBox', 'int16', [v for c in countries for v in c['box']])
    out += arr('worldLabel', 'int16', [v for c in countries for v in c['label']])
    out += arr('worldRingStart', 'uint16', ring_start)
    out += arr('worldRingOff', 'uint32', ring_off)
    out.append('  worldPts* = ' + nimstr(blob))
    out.append('  WorldCities* = %d' % len(CITIES))
    out.append('  worldCityNames*: array[%d, string] = [' % len(CITIES))
    for n, cc, la, lo in CITIES:
        out.append('    %s,' % json.dumps(n))
    out.append('  ]')
    out.append('  worldCityA2* = %s' % json.dumps(''.join(c[1] for c in CITIES)))
    out += arr('worldCityAt', 'int16', [v for c in CITIES for v in (int(round(c[3] * SCALE)), int(round(c[2] * SCALE)))])
    out.append('')
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'retro', 'worlddata.nim')
    open(dst, 'w').write('\n'.join(out))
    if dropped:
        print('dropped (too small):', ', '.join(dropped))
    print(len(countries), 'countries,', len(ring_off) - 1, 'rings,', npts, 'points,',
          len(blob), 'bytes of points')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'package/countries-50m.json')
