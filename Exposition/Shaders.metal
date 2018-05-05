#include <metal_stdlib>
#include <metal_math>

using namespace metal;

#define complexExtentX 3.5
#define complexExtentY 3

/// Convert a point on the screen to a point in the complex plane.
inline float2 screenToComplex(float2 point, float2 size, float2 zoom)
{
    const float scale = max(zoom.x/size.x, zoom.y/size.y);
    return (point - size/2) * scale;
}

inline float2 cross(float2 a, float2 b) {
    // <a.x, a.y> x <b.x, b.y>
    float real = a.x * b.x - a.y * b.y;
    float imag = a.y * b.x + a.x * b.y;
    return float2(real, imag);
}

inline float2 div(float2 a, float2 b) {
    float modulus = b.x * b.x + b.y * b.y;
    float real = a.x * b.x + a.y * b.y;
    float imag = a.y * b.x - a.x * b.y;
    return float2(real/modulus, imag/modulus);
}

inline float2 sub(float2 l, float2 r) {
    return float2(l.x - r.x, l.y - r.y);
}

float4 colorForIterationNewTon(float2 a, float2 c, int maxiters, float escape)
{
    for (int i = 0; i < maxiters; i++) {
        float2 a1 =  cross(cross(float2(3, 0), a), a);
        float2 a2 = cross(cross(a, a), a);
        float2 a3 = div(a2 - float2(1, 0), a1);
        a = a - cross(c, a3);

        if (length_squared(a) > escape) {
            float hue = (i+1-log2(log10(length_squared(a))/2))/maxiters*4 * M_PI_F + 3;
            return float4((cos(hue)+1)/2,
                          (-cos(hue+M_PI_F/3)+1)/2,
                          (-cos(hue-M_PI_F/3)+1)/2,
                          1);
        }
    }
    
    return float4(0, 0, 0, 1);
}

kernel void newtonShader(texture2d<float, access::write> output [[texture(0)]],
                        uint2 upos [[thread_position_in_grid]],
                         const device float2* parameters [[buffer(0)]])
{
    uint width = output.get_width();
    uint height = output.get_height();
    if (upos.x > width || upos.y > height) return;
    
    const device float2& screenPoint = parameters[0];
    const device float2& origin = parameters[1];
    const device float2& zoom = parameters[2];
    
    float2 uposf = float2(upos.x, upos.y);
    float2 size = float2(width, height);
    
    float2 z = screenToComplex(uposf - origin,
                               size,
                               zoom);
    float2 c = screenToComplex(screenPoint,
                               size,
                               zoom);
    
    output.write(float4(colorForIterationNewTon(z, c, 100, 50)), upos);
}
