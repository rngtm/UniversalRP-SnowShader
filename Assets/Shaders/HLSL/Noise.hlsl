/////////////////////////////////////////////////////////////////////////
// 3D Noise by uqone (from : https://www.shadertoy.com/view/Wl2XzW )
/////////////////////////////////////////////////////////////////////////
#define HASHSCALE1 float3(0.1031, 0.1031, 0.1031)

const float3x3 m3 = float3x3( 
    0.00,  0.80,  0.60,
	-0.80,  0.36, -0.48,
	-0.60, -0.48,  0.64 );

float3 hash(float3 p3)
{
	p3 = frac(p3 * HASHSCALE1);
	p3 += dot(p3, p3.yxz+19.19);
	return frac((p3.xxy + p3.yxx)*p3.zyx);
}

half3 noise( in float3 x )
{
	float3 p = floor(x);
	float3 f = frac(x);
	f = f*f*(3.0-2.0*f);
	
	return lerp(lerp(lerp( hash(p+float3(0,0,0)), 
	    hash(p+float3(1,0,0)),f.x),
					lerp( hash(p+float3(0,1,0)), 
						hash(p+float3(1,1,0)),f.x),f.y),
				lerp(lerp( hash(p+float3(0,0,1)), 
						hash(p+float3(1,0,1)),f.x),
					lerp( hash(p+float3(0,1,1)), 
						hash(p+float3(1,1,1)),f.x),f.y),f.z);
}
					
half3 fbm(in float3 q)
{
	float3 f  = 0.5000*noise( q ); q = mul(m3, q*2.01);
	f += 0.2500*noise( q ); q = mul(m3, q*2.02);
	f += 0.1250*noise( q ); q = mul(m3, q*2.03);
	f += 0.0625*noise( q ); q = mul(m3, q*2.04);
// #if 0
// 	f += 0.03125*noise( q ); q = mul(m3, q*2.05);
// 	f += 0.015625*noise( q ); q = mul(m3, q*2.06);
// 	f += 0.0078125*noise( q ); q = mul(m3, q*2.07);
// 	f += 0.00390625*noise( q ); q = mul(m3, q*2.08);  
// #endif
	return float3(f);
}