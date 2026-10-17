shader_type canvas_item;
render_mode unshaded;
uniform sampler2D palette : filter_nearest, repeat_disable;
uniform int row = 0;
void fragment() {
    int index = int(round(texture(TEXTURE,UV).r * 255.0));
    COLOR = texelFetch(palette,ivec2(index,row),0);
}
