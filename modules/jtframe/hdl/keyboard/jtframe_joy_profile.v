/* SPDX-License-Identifier: GPL-3.0-or-later
 * Per-player button profiles.
 *
 * Each player picks one of SLOTS stored profiles from the OSD. A profile
 * says, for every game button, which pad button drives it, so players can
 * swap in their own layout mid-game without touching MiSTer's input maps.
 *
 * NVRAM image (16 bytes per slot, SLOTS*16 bytes in total):
 *   byte 0..BUTTONS-1 : source pad button + 1 for game button k.
 *                       0 means "default" (game button k = pad button k),
 *                       so an all-zero image, which is what MiSTer sends
 *                       when no .nvm file exists, is the identity map.
 *   byte 6..15        : slot name, ASCII. A leading 0 means unnamed, and
 *                       the OSD shows "Slot N" instead.
 *
 * Joystick bits are active low, as in the rest of jtframe:
 *   [3:0] directions, [4+:BUTTONS] buttons, remaining bits passed through.
 */

module jtframe_joy_profile #(parameter
    BUTTONS = 6,    // 1..6
    SLOTS   = 8     // 1..8
)(
    input             rst,
    input             clk,

    input       [9:0] raw1, raw2,
    output reg  [9:0] joy1, joy2,

    // OSD: active slot per player, plus the edit page
    input       [2:0] sel1, sel2,
    input       [2:0] edit_slot,
    input      [17:0] edit_map,     // 3 bits per game button, 0-based pad button
    input             store,        // level from the OSD action bit
    output reg [17:0] slot_map,     // edit_slot's stored map, for status_set
    output reg        slot_push,    // one-cycle pulse: push slot_map to the OSD
    output reg        upload_req,   // one-cycle pulse: ask MiSTer to save NVRAM

    // NVRAM interface
    input       [6:0] nv_addr,
    input       [7:0] nv_din,
    input             nv_we,
    output reg  [7:0] nv_dout,

    // name readout for the OSD string
    input       [2:0] name_slot,
    input       [3:0] name_idx,     // 0..9
    output reg  [7:0] name_char
);

localparam NAMELEN = 10;

reg  [2:0] map  [0:SLOTS*6-1];      // 0-based source, used when vld is set
reg        vld  [0:SLOTS*6-1];
reg  [7:0] name [0:SLOTS*NAMELEN-1];

reg  [2:0] last_edit;
reg        last_store, pushed;
integer    i;

// ---------------------------------------------------------------- remap
function [9:0] remap;
    input [9:0] raw;
    input [2:0] slot;
    integer k, idx;
    begin
        remap = raw;
        for( k=0; k<BUTTONS; k=k+1 ) begin
            idx = slot*6+k;
            if( vld[idx] && map[idx] < BUTTONS )
                remap[4+k] = raw[4+map[idx]];
        end
    end
endfunction

always @(posedge clk) begin
    joy1 <= remap(raw1, sel1 < SLOTS ? sel1 : 3'd0);
    joy2 <= remap(raw2, sel2 < SLOTS ? sel2 : 3'd0);
end

// ---------------------------------------------------------------- storage
wire [2:0] nv_slot = nv_addr[6:4];
wire [3:0] nv_byte = nv_addr[3:0];

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        for( i=0; i<SLOTS*6; i=i+1 ) begin
            map[i] <= 0;
            vld[i] <= 0;
        end
        for( i=0; i<SLOTS*NAMELEN; i=i+1 ) name[i] <= 0;
        last_edit  <= 0;
        last_store <= 0;
        pushed     <= 0;
        slot_push  <= 0;
        upload_req <= 0;
    end else begin
        slot_push  <= 0;
        upload_req <= 0;
        last_store <= store;
        last_edit  <= edit_slot;

        if( nv_we && nv_slot < SLOTS ) begin
            if( nv_byte < 6 ) begin
                map[nv_slot*6+nv_byte] <= nv_din[2:0]-3'd1;
                vld[nv_slot*6+nv_byte] <= nv_din!=0;
            end else begin
                name[nv_slot*NAMELEN+nv_byte-6] <= nv_din;
            end
            pushed <= 0;    // refresh the edit page after a load
        end

        if( store && !last_store && edit_slot < SLOTS ) begin
            for( i=0; i<6; i=i+1 ) begin
                map[edit_slot*6+i] <= edit_map[i*3+:3];
                vld[edit_slot*6+i] <= i < BUTTONS;
            end
            upload_req <= 1;
        end

        // Show the stored map whenever the edit slot changes, and once
        // after reset or an NVRAM load.
        if( (edit_slot != last_edit || !pushed) && !nv_we ) begin
            pushed    <= 1;
            slot_push <= 1;
        end
    end
end

// edit page contents for the selected slot
always @* begin
    slot_map = 0;
    for( i=0; i<6; i=i+1 )
        slot_map[i*3+:3] = (edit_slot < SLOTS && vld[edit_slot*6+i]) ?
                           map[edit_slot*6+i] : i[2:0];
end

// NVRAM readback, same encoding as the load
always @* begin
    nv_dout = 0;
    if( nv_slot < SLOTS ) begin
        if( nv_byte < 6 )
            nv_dout = vld[nv_slot*6+nv_byte] ? {5'd0,map[nv_slot*6+nv_byte]}+8'd1 : 8'd0;
        else
            nv_dout = name[nv_slot*NAMELEN+nv_byte-6];
    end
end

// OSD name: the stored name, or "Slot N" padded with spaces when unnamed
always @* begin
    name_char = " ";
    if( name_slot < SLOTS && name_idx < NAMELEN ) begin
        if( name[name_slot*NAMELEN] != 0 ) begin
            name_char = name[name_slot*NAMELEN+name_idx];
            if( name_char < 8'h20 || name_char > 8'h7e ) name_char = " ";
        end else case( name_idx )
            0: name_char = "S";
            1: name_char = "l";
            2: name_char = "o";
            3: name_char = "t";
            5: name_char = "1" + {5'd0,name_slot};
            default: name_char = " ";
        endcase
    end
end

endmodule
