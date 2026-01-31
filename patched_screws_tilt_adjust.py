def probe_finalize(self, *args):
    # Creality variants may call:
    #  - probe_finalize(offsets, positions)
    #  - probe_finalize(positions)
    if len(args) == 1:
        offsets, positions = None, args[0]
    else:
        offsets, positions = args[0], args[1]

    self.results = []
    self.max_diff_error = False

    threads_factor = {0: 0.5, 1: 0.5, 2: 0.7, 3: 0.7, 4: 0.8, 5: 0.8, 6: 1.0, 7: 1.0}
    is_clockwise_thread = (self.thread & 1) == 0
    screw_diff = []

    def get_z(p):
        # tuple/list style: [x, y, z] or (x, y, z)
        if isinstance(p, (list, tuple)):
            return p[2]
        # object style: p.bed_z
        return p.bed_z

    if self.direction is not None:
        use_max = ((is_clockwise_thread and self.direction == 'CW')
                   or (not is_clockwise_thread and self.direction == 'CCW'))
        min_or_max = max if use_max else min
        i_base, z_base = min_or_max(
            enumerate([get_z(p) for p in positions]), key=lambda v: v[1])
    else:
        i_base, z_base = 0, get_z(positions[0])

    self.gcode.respond_info("01:20 means 1 full turn and 20 minutes, "
                            "CW=clockwise, CCW=counter-clockwise")

    for i, screw in enumerate(self.screws):
        z = get_z(positions[i])
        coord, name = screw
        if i == i_base:
            self.gcode.respond_info(
                "%s : x=%.1f, y=%.1f, z=%.5f" %
                (name + ' (base)', coord[0], coord[1], z))
            self.results.append({'name': name + ' (base)', 'x': coord[0],
                                 'y': coord[1], 'z': z, 'sign': 'CW',
                                 'adjust': '00:00'})
        else:
            diff = z_base - z
            screw_diff.append(abs(diff))
            if abs(diff) < 0.001:
                adjust = 0
            else:
                adjust = diff / threads_factor.get(self.thread, 0.5)

            if is_clockwise_thread:
                sign = "CW" if adjust >= 0 else "CCW"
            else:
                sign = "CCW" if adjust >= 0 else "CW"

            adjust = abs(adjust)
            full_turns = math.trunc(adjust)
            minutes = round((adjust - full_turns) * 60, 0)

            self.gcode.respond_info(
                "%s : x=%.1f, y=%.1f, z=%.5f : adjust %s %02d:%02d" %
                (name, coord[0], coord[1], z, sign, full_turns, minutes))
            self.results.append({'name': name, 'x': coord[0], 'y': coord[1],
                                 'z': z, 'sign': sign,
                                 'adjust': "%02d:%02d" % (full_turns, minutes)})

    if self.max_diff and any((d > self.max_diff) for d in screw_diff):
        self.max_diff_error = True
        raise self.gcode.error(
            "bed level exceeds configured limits ({}mm)! "
            "Adjust screws and restart print.".format(self.max_diff))
