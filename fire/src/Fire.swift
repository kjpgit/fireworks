import func Foundation.log10f


private let VELOCITY: Float         = 0.3
private let GRAVITY: Float          = -0.08

private let COLORS: [Color4] = [
    Color4(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
    Color4(r: 0.0, g: 1.0, b: 0.0, a: 1.0),
    Color4(r: 1.0, g: 1.0, b: 0.0, a: 1.0),
    Color4(r: 0.0, g: 1.0, b: 1.0, a: 1.0),
    Color4(r: 1.0, g: 0.0, b: 0.5, a: 1.0),
    Color4(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
    Color4(r: 1.0, g: 0.2, b: 0.2, a: 1.0),
]

private func get_random_color() -> Color4 {
    let i = random_range(0, COLORS.count - 1)
    return COLORS[i]
}


// Return a position.
// Simulate air drag - velocity tapers off exponentially
private func _get_flight(vel: Float, secs: Float) -> Float {
    let x = log10f(1 + secs * 10.0)
    return x * vel
}


// Record the starting point of a flare.
// We have the entire trajectory (path) from the beginning.
struct Flare {
    let velocity_vec: Vector3
    let start_time: TimeUS
    let duration_secs: Float

    // How far back the trail goes (plume mode)
    let trail_secs: Float  

    let color: Color4
    let size: Float

    func getSecondsElapsed(time: TimeUS) -> Float {
        if time < start_time {
            return 0
        }
        return Float(time - start_time) / 1000000
    }

    func pointAtTime(secs: Float, orig_pos: Vector3) -> Vector3 {
        var ret = orig_pos
        ret.x += _get_flight(velocity_vec.x, secs: secs)
        ret.y += _get_flight(velocity_vec.y, secs: secs)
        //ret.z += _get_flight(velocity_vec.z, secs: secs)

        // Gravity
        ret.y += (GRAVITY / Float(2.0) * secs * secs)

        return ret
    }

    func colorAtTime(secs: Float) -> Color4 {
        // linear fade out is fine
        let percent = secs / duration_secs
        var ret = color
        ret.a *= (1 - percent)
        return ret
    }
}


class Firework : Drawable {
    var pos: Vector3
    let type: Int
    var m_flares = [Flare]()

    init(pos: Vector3, type: Int) {
        precondition(type >= 0)
        precondition(type <= 1)
        self.pos = pos
        self.type = type
    }

    func add_flares(start_time: TimeUS, aspect_x: Float) {
        let count = 400
        let orig_color = get_random_color()
        for _ in 0..<count {
            var velocity = RandomUniformUnitVector()

            // for now, don't animate z, to stay in device space
            velocity.z = 0

            // Aspect correction.  Otherwise we get ovalish fireworks.
            velocity.x *= aspect_x

            // tune the velocity
            let speed_variance = random_range(1.0, 1.5)
            velocity.x *= VELOCITY * speed_variance
            velocity.y *= VELOCITY * speed_variance

            var color = orig_color
            color.r += random_range(-0.3, 0.3)
            color.b += random_range(-0.3, 0.3)
            color.g += random_range(-0.3, 0.3)
            color.a = random_range(0.7, 4.0)

            let duration_secs = random_range(0.5, 3.0)
            let trail_secs = random_range(0.3, 0.7)
            let size = random_range(0.003, 0.005)

            let f = Flare(velocity_vec: velocity,
                        start_time: start_time,
                        duration_secs: duration_secs,
                        trail_secs: trail_secs,
                        color: color, 
                        size: size)
            m_flares.append(f)
        }
    }

    func draw(time: TimeUS, 
            inout bv: BufferWrapper, 
            inout bc: BufferWrapper) {
        if self.type == 0 {
            // classic particle only
            for flare in self.m_flares {
                render_flare_simple(self, flare: flare, 
                        time: time, bv: &bv, bc: &bc) 
            }
        } else {
            // long trail
            for flare in self.m_flares {
                render_flare_trail(self, flare: flare, 
                        time: time, bv: &bv, bc: &bc) 
            }
        }
    }
}



private func render_flare_simple(fw: Firework, flare: Flare, time: TimeUS, 
        inout bv: BufferWrapper, inout bc: BufferWrapper) {
    let secs = flare.getSecondsElapsed(time)
    if secs > flare.duration_secs {
        return
    }
    let p = flare.pointAtTime(secs, orig_pos: fw.pos)
    var color = flare.colorAtTime(secs)
    if secs > (flare.duration_secs - 0.1) {
        // flash out
        color.a = 1.0
    }
    //print(p)
    draw_triangle_2d(&bv, p, flare.size)
    draw_triangle_color(&bc, color)
    draw_triangle_2d_ups(&bv, p, flare.size)
    draw_triangle_color(&bc, color)
}


private func render_flare_trail(fw: Firework, flare: Flare, time: TimeUS, 
        inout bv: BufferWrapper, inout bc: BufferWrapper) {

    let PLUME_FADE: Float       = 0.90
    // If this is too small, flickering happens when the dots move
    let PLUME_STEP_SECS: Float  = 0.02

    var secs = flare.getSecondsElapsed(time)
    if secs > flare.duration_secs {
        return
    }
    var color = flare.colorAtTime(secs)
    var plume_secs = Float(0)
    var size = flare.size
    var first = true

    while true {
        let p = flare.pointAtTime(secs, orig_pos: fw.pos)
        draw_triangle_2d(&bv, p, size)
        draw_triangle_color(&bc, color)
        if first {
            draw_triangle_2d_ups(&bv, p, size)
            draw_triangle_color(&bc, color)
            first = false
        }
        
        size *= 0.95
        color.a *= PLUME_FADE
        secs -= PLUME_STEP_SECS
        plume_secs += PLUME_STEP_SECS
        if secs < 0 || plume_secs > flare.trail_secs {
            return
        }
    }
}


private func draw_triangle_2d(inout b: BufferWrapper, 
                              _ pos: Vector3, _ size: Float) {
    guard b.has_available(12) else {
        return
    }

    b.append_raw(pos.x - size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x + size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x)
    b.append_raw(pos.y + size)
    b.append_raw(pos.z)
    b.append_raw(1.0)
}


// upside down
private func draw_triangle_2d_ups(inout b: BufferWrapper, _ pos: Vector3, _ size: Float) {
    guard b.has_available(12) else {
        return
    }

    b.append_raw(pos.x - size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x + size)
    b.append_raw(pos.y)
    b.append_raw(pos.z)
    b.append_raw(1.0)

    b.append_raw(pos.x)
    b.append_raw(pos.y - size)
    b.append_raw(pos.z)
    b.append_raw(1.0)
}


private func draw_triangle_color(inout b: BufferWrapper, _ color: Color4) {
    guard b.has_available(12) else {
        return
    }

    b.append_raw_color4(color)
    b.append_raw_color4(color)
    b.append_raw_color4(color)
}
