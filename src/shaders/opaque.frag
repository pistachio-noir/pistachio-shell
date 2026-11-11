// The Overview's window pictures, drawn solid (owner's report, 12 November 2026): a window made
// see-through (a Hyprland opacity rule, a terminal's background opacity) arrives with alpha; its
// colours are premultiplied, so dividing by alpha gives them back as the window would look opaque.
// Compiled to opaque.frag.qsb with Qt's qsb (see the comment in panels/OverviewThumb.qml).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.004 ? c.rgb / c.a : c.rgb;
    fragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * qt_Opacity;
}
