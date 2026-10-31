// Halo puck: wired Snapcast client in a round printed shell.
// XIAO ESP32-S3 + PCM5102A DAC + 1000 mAh LiPo + 16-pixel WS2812 ring +
// 12 mm tactile switch under a floating cap. Clip and lanyard attachments.
//
// Render one part at a time:
//   openscad -D 'part="base"'     -o halo-base.stl     halo.scad
//   openscad -D 'part="tray"'     -o halo-tray.stl     halo.scad
//   openscad -D 'part="lid"'      -o halo-lid.stl      halo.scad   (clear PETG)
//   openscad -D 'part="cap"'      -o halo-cap.stl      halo.scad
//   openscad -D 'part="clip"'     -o halo-clip.stl     halo.scad   (PETG)
//   openscad -D 'part="coupon"'   -o halo-coupon.stl   halo.scad   (fit test, print first)
//   openscad -D 'part="assembly"' halo.scad                        (preview only)
//
// Every dimension below is a parameter. Change, re-render, print.
// Z is up. Z=0 is the outside of the floor.

part = "assembly";   // base | tray | lid | cap | clip | coupon | assembly
$fn = 96;

// ---------- printer fit ----------
fit       = 0.25;   // clearance for parts that must slide (cap in collar)
snap_fit  = 0.15;   // clearance for parts that press together (lid lip in wall)
insert_d  = 4.0;    // hole for M3 heat-set insert (M3 x 4 x 5)
insert_h  = 5.2;
screw_d   = 3.4;    // M3 clearance
screw_head_d = 6.2; // countersink for M3 head in the floor
screw_head_h = 2.0;

// ---------- components ----------
batt      = [50, 34, 5.0];      // 053450 LiPo
xiao      = [21, 17.5, 1.2];    // XIAO ESP32-S3 PCB
xiao_usb  = [9.0, 3.3];         // USB-C port width, height above PCB
dac       = [30, 18, 1.6];      // PCM5102A module PCB (jack unused; panel jack wired)
sw        = [12, 12, 7.3];      // 12 mm tactile switch, height to plunger top
sw_plunger_d = 3.6;
ring_od   = 44.5;               // 16-pixel WS2812 ring
ring_id   = 31.7;
ring_h    = 3.2;                // PCB + LED package
jack_d    = 6.2;                // panel-mount 3.5 mm jack, M6 thread
power_sw  = [8.6, 3.6, 5];      // SS12D00 slide switch body
power_sw_lever = [3.2, 7.5];    // lever slot width, travel length

// ---------- shell ----------
wall      = 2.0;
floor_t   = 1.6;
inner_r   = 32;                 // inside radius; XIAO corner sits at r 31.2
outer_r   = inner_r + wall;
batt_pocket_h = batt[2] + 0.3;
tray_z    = floor_t + batt_pocket_h;      // 6.9, underside of tray
tray_t    = 1.2;
board_z   = tray_z + tray_t;              // 8.1, boards and switch sit here
wall_top  = 15.5;                         // top of base wall
lid_t     = 1.2;
lid_z     = 17.5;                         // underside of lid top
lid_top   = lid_z + lid_t;                // 18.7
ring_z    = 13.5;                         // ring PCB underside
boss_r    = 28.5;                         // screw bosses radius (post edge stays inside the wall)
boss_d    = 8;
boss_angles = [45, 135, 225, 315];
post_d    = 6;                            // lid posts (carry the inserts)

// ---------- cap and collar ----------
cap_d        = 28;
cap_t        = 1.5;
cap_top      = lid_top + 0.6;             // stands proud of the lid
collar_id    = cap_d + 2*fit;
collar_wall  = 0.8;
collar_od    = collar_id + 2*collar_wall;
collar_bottom = 13.0;
flange_t     = 0.6;
flange_od    = collar_od - 0.4;           // sits under the collar, cannot pass up
plunger_top  = board_z + sw[2];           // 15.4
cap_gap      = 0.15;                      // cap boss hovers this far above plunger at rest

// ---------- placement (angles measured from +X, counter-clockwise) ----------
xiao_pos   = [-19.5, 0];   // USB-C faces 180 deg
dac_pos    = [18, 0];      // long axis along Y
jack_angle = 90;
jack_z     = 11;           // tray is notched under it
power_angle = 250;
power_z    = 11;
usb_z      = board_z + xiao[2] + xiao_usb[1]/2;
lanyard_angle = 90;
lanyard_z  = 3;
lanyard_hole = 3.4;

// ---------- attachments ----------
with_lanyard = true;
with_clip    = true;        // clip screws under the two rear floor screws
clip_angles  = [225, 315];
clip_t       = 1.6;
clip_len     = 34;
clip_gap     = 1.2;         // shirt thickness it grips

// ========================================================================
module ring2d(ro, ri) difference(){ circle(ro); circle(ri); }
module at_angle(a, r) translate([r*cos(a), r*sin(a), 0]) rotate([0,0,a]) children();
module rbox(size, r=1) { linear_extrude(size[2]) offset(r) offset(-r) square([size[0], size[1]], center=true); }

// ------------------------------------------------------------ base
module base() {
  difference() {
    union() {
      cylinder(r=outer_r, h=wall_top);
      // lanyard tab
      if (with_lanyard) at_angle(lanyard_angle, outer_r-1)
        translate([0, 0, lanyard_z]) rbox([7, 10, 7], 1.5);   // local X is radial here
    }
    // cavity
    translate([0,0,floor_t]) cylinder(r=inner_r, h=50);
    // USB-C slot for the XIAO
    at_angle(180, outer_r) translate([0, 0, usb_z]) cube([wall*3, xiao_usb[0]+1.0, xiao_usb[1]+0.9], center=true);
    // panel jack
    at_angle(jack_angle, outer_r) translate([0,0,jack_z]) rotate([0,90,0]) cylinder(d=jack_d, h=wall*3, center=true);
    // power switch lever slot
    at_angle(power_angle, outer_r) translate([0,0,power_z]) cube([wall*3, power_sw_lever[1], power_sw_lever[0]], center=true);
    // lanyard hole, tangential
    if (with_lanyard) at_angle(lanyard_angle, outer_r+2.5) translate([0,0,lanyard_z+3.5]) rotate([90,0,0]) cylinder(d=lanyard_hole, h=20, center=true);
    // floor screw holes with countersink
    for (a=boss_angles) at_angle(a, boss_r) {
      translate([0,0,-1]) cylinder(d=screw_d, h=20);
      translate([0,0,-0.01]) cylinder(d=screw_head_d, h=screw_head_h);
    }
  }
  // bosses the tray rests on
  for (a=boss_angles) at_angle(a, boss_r) difference() {
    translate([0,0,floor_t-0.01]) cylinder(d=boss_d, h=tray_z-floor_t+0.01);
    translate([0,0,-1]) cylinder(d=screw_d, h=20);
  }
  // battery locating ribs
  for (s=[-1,1]) translate([0, s*(batt[1]/2+0.8), floor_t]) rbox([batt[0]-10, 1.2, 3.5], 0.4);
  // power switch cradle: two small posts the switch body is glued between
  at_angle(power_angle, inner_r-power_sw[1]/2-0.6) translate([0,0,board_z-4])
    for (s=[-1,1]) translate([0, s*(power_sw[0]/2+1.2), 0]) rbox([power_sw[1]+1.2, 1.6, 5], 0.3);
}

// ------------------------------------------------------------ tray
module tray() {
  difference() {
    union() {
      translate([0,0,tray_z]) cylinder(r=inner_r-0.4, h=tray_t);
      // edge stops the boards drop between (the wall and USB slot locate the XIAO's outer edge)
      translate([0,0,board_z-0.01]) {
        translate(xiao_pos) stops(xiao, [1,0,1,1]);
        translate(dac_pos)  stops([dac[1], dac[0], dac[2]], [1,1,1,1]);   // DAC long axis along Y
        stops(sw, [1,1,1,1]);
      }
    }
    // notch under the panel jack body
    at_angle(jack_angle, inner_r) translate([-6, 0, tray_z-1]) cube([14, 12, 10], center=true);
    // notch for the power switch cradle
    at_angle(power_angle, inner_r) translate([-3, 0, tray_z-1]) cube([8, power_sw[0]+6, 10], center=true);
    // screw pass-through under the lid posts
    for (a=boss_angles) at_angle(a, boss_r) translate([0,0,tray_z-1]) cylinder(d=screw_d, h=10);
    // switch pins and wire pass-through
    translate([0,0,tray_z-1]) {
      for (x=[-1,1], y=[-1,1]) translate([x*3.25, y*2.25, 0]) cylinder(d=1.4, h=10);
      translate([0, -batt[1]/2+4, 0]) rbox([8, 4, 10], 1);     // battery leads
      translate(xiao_pos) translate([0,0,0]) rbox([14, 10, 10], 1);  // under the XIAO: battery pads
    }
  }
}
module stops(b, edges) {
  // small blocks at the middle of each edge: +x, -x, +y, -y. 0.8 wide, 1.4 tall, 5 long.
  g = 0.25;
  if (edges[0]) translate([ b[0]/2+g+0.4, 0, 0.7]) cube([0.8, 5, 1.4], center=true);
  if (edges[1]) translate([-b[0]/2-g-0.4, 0, 0.7]) cube([0.8, 5, 1.4], center=true);
  if (edges[2]) translate([0,  b[1]/2+g+0.4, 0.7]) cube([5, 0.8, 1.4], center=true);
  if (edges[3]) translate([0, -b[1]/2-g-0.4, 0.7]) cube([5, 0.8, 1.4], center=true);
}

// ------------------------------------------------------------ lid (clear PETG)
module lid() {
  difference() {
    union() {
      // top disc
      translate([0,0,lid_z]) cylinder(r=outer_r, h=lid_t);
      // outer skirt down onto the wall top
      translate([0,0,wall_top]) difference() { cylinder(r=outer_r, h=lid_z-wall_top+0.01); translate([0,0,-1]) cylinder(r=inner_r+snap_fit, h=10); }
      // alignment lip that drops inside the wall
      translate([0,0,wall_top-2]) difference() { cylinder(r=inner_r-snap_fit, h=2.01); translate([0,0,-1]) cylinder(r=inner_r-snap_fit-1.0, h=10); }
      // collar that guides the cap
      translate([0,0,collar_bottom]) difference() { cylinder(d=collar_od, h=lid_z-collar_bottom+0.01); translate([0,0,-1]) cylinder(d=collar_id, h=10); }
      // ring cradle: four ribs the ring rests on
      for (a=[22.5, 112.5, 202.5, 292.5]) rotate([0,0,a]) translate([ring_id/2+0.3, -1, ring_z-1.2]) cube([(ring_od-ring_id)/2-0.6, 2, lid_z-ring_z+1.2]);
      // lid posts carrying the inserts (screws come up from the floor)
      for (a=boss_angles) at_angle(a, boss_r) translate([0,0,board_z]) cylinder(d=post_d, h=lid_z-board_z+0.01);
    }
    // cap opening
    translate([0,0,lid_z-1]) cylinder(d=collar_id, h=10);
    // insert holes in the posts
    for (a=boss_angles) at_angle(a, boss_r) translate([0,0,board_z-0.01]) cylinder(d=insert_d, h=insert_h);
  }
}

// ------------------------------------------------------------ cap
module cap() {
  cap_bottom = collar_bottom - flange_t;  // flange rests under the collar
  difference() {
    union() {
      translate([0,0,cap_top-cap_t]) cylinder(d=cap_d, h=cap_t);
      // skirt
      translate([0,0,cap_bottom]) difference() { cylinder(d=cap_d, h=cap_top-cap_t-cap_bottom+0.01); translate([0,0,-1]) cylinder(d=cap_d-2*1.0, h=50); }
      // flange
      translate([0,0,cap_bottom]) cylinder(d=flange_od, h=flange_t);
      // boss that presses the switch plunger
      translate([0,0,plunger_top+cap_gap]) cylinder(d=sw_plunger_d+3, h=cap_top-cap_t-plunger_top-cap_gap+0.01);
    }
    // a shallow finger dish on top
    translate([0,0,cap_top+22]) sphere(r=23);
  }
}

// ------------------------------------------------------------ clip (PETG)
module clip() {
  // Badge-style pocket clip on the back (floor) of the puck. Worn with the jack at
  // 12 o'clock, so the clip opens downward: a plate caught under the two rear floor
  // screws, a U-bend at the top, and a leaf-spring arm running back down with a
  // flared tip. Print in PETG, flat on its back, arm up.
  p = [for (a=clip_angles) [boss_r*cos(a), boss_r*sin(a)]];
  w = 12; top_y = 24; bend_r = clip_gap/2 + clip_t;
  difference() {
    union() {
      // plate: two screw pads joined to a spine running up to the bend
      translate([0,0,-clip_t]) hull() for (q=p) translate(q) cylinder(d=10, h=clip_t);
      translate([-w/2, p[0][1], -clip_t]) cube([w, top_y - p[0][1], clip_t]);
      // U-bend at the top edge
      translate([0, top_y, -bend_r]) rotate([0,90,0]) difference() {
        cylinder(r=bend_r, h=w, center=true);
        cylinder(r=bend_r-clip_t, h=w+2, center=true);
        translate([0,-bend_r-1,-w]) cube([bend_r*2+2, bend_r+1, w*2]);
      }
      // arm with a flared tip
      translate([-w/2, -clip_len + top_y, -2*bend_r]) cube([w, clip_len, clip_t]);
      translate([-w/2, -clip_len + top_y, -2*bend_r]) rotate([-12,0,0]) translate([0,-3,0]) cube([w, 4, clip_t]);
    }
    for (q=p) translate([q[0], q[1], -clip_t-1]) cylinder(d=screw_d, h=10);
  }
}
module rbox_corner(size, r=1) translate([size[0]/2, size[1]/2, 0]) rbox(size, r);

// ------------------------------------------------------------ fit coupon
module coupon() {
  // print this first: a cap collar at three clearances and a lip at two.
  for (i=[0:2]) translate([i*22, 0, 0]) difference() {
    cylinder(d=20, h=4);
    translate([0,0,-1]) cylinder(d=12 + 2*(0.2 + i*0.1), h=10);
  }
  for (i=[0:2]) translate([i*22, 24, 0]) cylinder(d=12, h=6);
  for (i=[0:1]) translate([i*22, 46, 0]) difference() { cube([18, 18, 4], center=true); cube([10 + 2*(0.4 + i*0.2), 10 + 2*(0.4 + i*0.2), 10], center=true); }
  translate([44, 46, 0]) cube([10, 10, 4], center=true);
  translate([-14, 60, 0]) linear_extrude(0.8) text("fit 0.2 .3 .4  lip .4 .6", size=4);
}

// ------------------------------------------------------------ reference components (preview only)
module components() {
  color("silver") translate([-batt[0]/2, -batt[1]/2, floor_t+0.15]) cube(batt);
  color("darkgreen") translate([xiao_pos[0]-xiao[0]/2, xiao_pos[1]-xiao[1]/2, board_z]) cube(xiao);
  color("purple") translate([dac_pos[0]-dac[1]/2, dac_pos[1]-dac[0]/2, board_z]) cube([dac[1], dac[0], dac[2]]);
  color("dimgray") translate([-sw[0]/2, -sw[1]/2, board_z]) cube([sw[0], sw[1], sw[2]-1.5]);
  color("dimgray") translate([0,0,board_z]) cylinder(d=sw_plunger_d, h=sw[2]);
  color("black") translate([0,0,ring_z]) linear_extrude(ring_h) ring2d(ring_od/2, ring_id/2);
}

module assembly() {
  color("lightgray") base();
  color("gray") tray();
  color("lightblue", 0.45) lid();
  color("white") cap();
  if (with_clip) color("orange") clip();
  components();
}

if (part == "base") base();
else if (part == "tray") tray();
else if (part == "lid") lid();
else if (part == "cap") rotate([180,0,0]) translate([0,0,-cap_top]) cap();  // printed upside down: top face on the bed
else if (part == "clip") translate([0,0,2*(clip_gap/2+clip_t)]) clip();
else if (part == "none") ;
else if (part == "coupon") coupon();
else assembly();
