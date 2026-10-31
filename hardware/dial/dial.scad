// Dial: desk box for the SilentDisco server (Raspberry Pi 3B).
// Front face: 16-pixel WS2812 ring behind four quadrant windows (one per colour)
// and a 0.96" OLED showing the join QR. Ethernet + USB out the right wall,
// power + HDMI out the back. Lid hooks under the back wall and screws at the front.
//
//   openscad -D 'part="base"'   -o dial-base.stl   dial.scad
//   openscad -D 'part="lid"'    -o dial-lid.stl    dial.scad
//   openscad -D 'part="window"' -o dial-window.stl dial.scad   (clear PETG)
//   openscad -D 'part="assembly"' dial.scad                     (preview)
//
// Origin: outside front-left-bottom corner of the box. X right, Y back, Z up.

part = "assembly";   // base | lid | window | assembly
$fn = 72;

// ---------- printer fit ----------
fit       = 0.25;
insert_d  = 4.0;    // M3 heat-set insert
insert_h  = 5.2;
screw_d   = 3.4;
screw_head_d = 6.2;
screw_head_h = 2.0;

// ---------- box ----------
outer     = [114, 80, 42];
wall      = 2.0;
front_t   = 3.0;      // front wall is thicker: it carries the windows
floor_t   = 2.0;
lid_t     = 2.0;
inner     = [outer[0]-2*wall, outer[1]-front_t-wall, outer[2]-floor_t-lid_t];
corner_r  = 4;
label     = "SILENT DISCO";
label_size = 5;

// ---------- Raspberry Pi 3B ----------
pi        = [85, 56, 1.6];
pi_holes  = [[3.5,3.5],[61.5,3.5],[3.5,52.5],[61.5,52.5]];   // from the SD-card / HDMI corner
pi_mount  = "peg";    // "peg": 2.5 mm press-fit pegs, no screws. "screw": holes for M2.5 self-tap.
standoff_h = 5;
pi_pos    = [wall + 21, front_t + inner[1] - pi[1] - 1.5];   // PCB corner (x,y); ports stick out 1.5 past the walls
pi_z      = floor_t + standoff_h;                             // PCB underside
// right-wall ports (USB x2, Ethernet) along the PCB's x=85 edge, y positions from the drawing
right_ports = [[10.25, 16, 13.5], [29, 15.5, 16], [47, 15.5, 16]];   // [y centre, width, height above PCB]
// back-wall ports along the PCB's y=0 edge: micro-USB, HDMI, audio
back_ports  = [[10.6, 8.5, 3.5], [32, 16, 6.5], [53.5, 7.5, 7]];      // [x centre, width, height above PCB]

// ---------- face parts ----------
ring_od   = 44.5;
ring_id   = 31.7;
ring_h    = 3.2;
ring_c    = [33, 21];                 // window centre on the face (x, z)
win_ro    = 22.8;                     // quadrant windows, outer radius
win_ri    = 15.0;                     // inner radius (centre stays opaque)
rib_w     = 2.5;                      // ribs between quadrants
window_t  = 1.2;                      // clear disc
window_d  = ring_od + 2.5;

oled_pcb  = [27.5, 27.5];
oled_holes = [23.5, 23.5];            // hole pitch, adjust to your module
oled_hole_d = 2.0;                    // M2 self-tap
oled_glass = [26, 14];                // window cut
oled_glass_offset = [0, -2];          // glass centre relative to PCB centre (pins at the top)
oled_c    = [86, 21];                 // glass centre on the face (x, z)
oled_post_h = 2.5;

// ---------- lid ----------
lid_hook_x = [16, 98];                // where the rear hooks sit
lid_screws = [[5.5, front_t + 5.5], [outer[0]-5.5, front_t + 5.5]];
vent_slots = 7;

// ========================================================================
module rrect(size, r) { linear_extrude(size[2]) offset(r) offset(-r) square([size[0], size[1]]); }
module rbox_c(size, r=1) translate([-size[0]/2, -size[1]/2, 0]) rrect(size, r);

module base() {
  difference() {
    rrect(outer, corner_r);
    // cavity
    translate([wall, front_t, floor_t]) cube([inner[0], inner[1], 60]);
    // right wall port openings
    for (p = right_ports)
      translate([outer[0]-wall-1, pi_pos[1] + p[0] - p[1]/2 - 1, pi_z + pi[2] - 0.5]) cube([wall+2, p[1]+2, p[2]+1.5]);
    // back wall port openings
    for (p = back_ports)
      translate([pi_pos[0] + p[0] - p[1]/2 - 1, outer[1]-wall-1, pi_z + pi[2] - 0.5]) cube([p[1]+2, wall+2, p[2]+1.5]);
    // quadrant windows and the recess for the clear disc
    translate([ring_c[0], 0, ring_c[1]]) rotate([-90,0,0]) {
      for (a=[0,90,180,270]) rotate([0,0,a+45]) translate([0,0,-1]) linear_extrude(front_t+2) intersection() {
        difference() { circle(win_ro); circle(win_ri); }
        polygon([[0,0],[100*cos(45-45+ 0),100*sin(0)],[100*cos(90),100*sin(90)]]);  // first quadrant
      }
      translate([0,0,front_t-window_t]) cylinder(d=window_d+2*fit, h=10);
    }
    // ribs are what is left between the four cuts; the centre disc stays opaque.
    // OLED glass window
    translate([oled_c[0], -1, oled_c[1]]) rotate([-90,0,0]) rbox_c([oled_glass[0]+0.6, oled_glass[1]+0.6, front_t+2], 1);
    // engraved label under the OLED
    translate([oled_c[0], 0.6, 8]) rotate([90,0,0]) linear_extrude(1) text(label, size=label_size, halign="center", valign="center", font="Liberation Sans:style=Bold");
    // floor vents under the Pi, and left wall vents
    for (i=[0:vent_slots-1]) translate([pi_pos[0] + 12 + i*9, pi_pos[1] + 8, -1]) rrect([3, 40, floor_t+2], 1.4);
    for (i=[0:4]) translate([-1, front_t + 30 + i*8, 10]) cube([wall+2, 3, 20]);
    // back wall lip clearance is a union below; nothing to cut here.
  }
  // ring cradle on the inside of the front wall
  translate([ring_c[0], front_t, ring_c[1]]) rotate([-90,0,0]) difference() {
    cylinder(d=ring_od+2*fit+3, h=ring_h+0.6);
    translate([0,0,-1]) cylinder(d=ring_od+2*fit, h=10);
    // gap for the ring's wires
    translate([-4, -ring_od/2-5, -1]) cube([8, 6, 10]);
  }
  translate([ring_c[0], front_t, ring_c[1]]) rotate([-90,0,0]) cylinder(d=ring_id-2*fit, h=1.2);   // centre boss keeps it concentric
  // OLED posts
  translate([oled_c[0]-oled_glass_offset[0], front_t, oled_c[1]-oled_glass_offset[1]])
    for (x=[-1,1], z=[-1,1]) translate([x*oled_holes[0]/2, 0, z*oled_holes[1]/2]) rotate([-90,0,0]) difference() {
      cylinder(d=oled_hole_d+2.4, h=oled_post_h);
      translate([0,0,-1]) cylinder(d=oled_hole_d, h=10);
    }
  // Pi standoffs
  for (h = pi_holes) translate([pi_pos[0]+h[0], pi_pos[1]+h[1], floor_t-0.01]) {
    if (pi_mount == "peg") { cylinder(d=7, h=standoff_h); cylinder(d=2.5, h=standoff_h+pi[2]+1.5); }
    else difference() { cylinder(d=7, h=standoff_h); translate([0,0,1]) cylinder(d=2.2, h=10); }
  }
  // lid screw bosses at the front corners
  for (s = lid_screws) translate([s[0], s[1], floor_t-0.01]) difference() {
    cylinder(d=8, h=inner[2]+0.01);
    translate([0,0,inner[2]-insert_h]) cylinder(d=insert_d, h=insert_h+1);
  }
  // back wall lip the lid hooks slide under
  translate([wall+2, outer[1]-wall-1.5, floor_t+inner[2]-4]) cube([inner[0]-4, 1.5, 1.5]);
}

module lid() {
  z0 = floor_t + inner[2];   // underside of lid
  difference() {
    union() {
      translate([0,0,z0]) rrect([outer[0], outer[1], lid_t], corner_r);
      // inner lip on front, left and right
      translate([wall+fit, front_t+fit, z0-2]) difference() {
        cube([inner[0]-2*fit, inner[1]-2*fit-2, 2.01]);
        translate([1.2, 1.2, -1]) cube([inner[0]-2*fit-2.4, inner[1], 5]);
      }
      // rear hooks
      for (x = lid_hook_x) translate([x-5, outer[1]-wall-3.2, z0-5.5]) {
        cube([10, 1.5, 5.5]);                       // drop
        translate([0, 0, 0]) cube([10, 3.2-0.3, 1.2]);  // toe that goes under the lip
      }
    }
    // front screws, countersunk
    for (s = lid_screws) translate([s[0], s[1], z0-1]) { cylinder(d=screw_d, h=10); translate([0,0,1+lid_t-screw_head_h]) cylinder(d=screw_head_d, h=5); }
    // vents over the Pi
    for (i=[0:vent_slots-1]) translate([pi_pos[0] + 12 + i*9, pi_pos[1] + 8, z0-1]) rrect([3, 40, lid_t+2], 1.4);
    // clearance notches so the hooks clear the bosses: none needed
  }
}

module window() {
  cylinder(d=window_d, h=window_t);
}

module components() {
  color("darkgreen") translate([pi_pos[0], pi_pos[1], pi_z]) cube(pi);
  for (p = right_ports) color("silver") translate([pi_pos[0]+pi[0]-14, pi_pos[1]+p[0]-p[1]/2, pi_z+pi[2]]) cube([17, p[1], p[2]]);
  for (p = back_ports) color("silver") translate([pi_pos[0]+p[0]-p[1]/2, pi_pos[1]-1, pi_z+pi[2]]) cube([p[1], 10, p[2]]);
  color("black") translate([ring_c[0], front_t+0.6, ring_c[1]]) rotate([-90,0,0]) linear_extrude(ring_h) difference(){ circle(ring_od/2); circle(ring_id/2); }
  color("navy") translate([oled_c[0]-oled_glass_offset[0]-oled_pcb[0]/2, front_t+oled_post_h, oled_c[1]-oled_glass_offset[1]-oled_pcb[1]/2]) cube([oled_pcb[0], 1.2, oled_pcb[1]]);
}

module assembly() {
  color("lightgray") base();
  color("lightblue", 0.5) translate([ring_c[0], front_t-window_t, ring_c[1]]) rotate([-90,0,0]) window();
  color("gray", 0.5) lid();
  components();
}

if (part == "base") base();
else if (part == "lid") translate([0, outer[1], outer[2]]) rotate([180,0,0]) lid();   // printed upside down
else if (part == "window") window();
else if (part == "none") ;
else assembly();
