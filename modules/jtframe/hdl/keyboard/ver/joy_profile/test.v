`timescale 1ns/1ps
// Self-checking test for jtframe_joy_profile. Run: ./sim.sh
module test;

reg         rst=1, clk=0;
reg   [9:0] raw1=10'h3ff, raw2=10'h3ff;
wire  [9:0] joy1, joy2;
reg   [2:0] sel1=0, sel2=0, edit_slot=0, name_slot=0;
reg  [17:0] edit_map=0;
reg         store=0, nv_we=0;
reg   [6:0] nv_addr=0;
reg   [7:0] nv_din=0;
reg   [3:0] name_idx=0;
wire  [7:0] nv_dout, name_char;
wire [17:0] slot_map;
wire        slot_push, upload_req;
integer     errors=0, pushes=0, uploads=0, k;

always #5 clk = ~clk;
always @(posedge clk) begin
    if( slot_push  ) pushes  = pushes+1;
    if( upload_req ) uploads = uploads+1;
end

jtframe_joy_profile uut(.*);

task check10(input [9:0] got, input [9:0] want, input [8*40:1] what);
    if( got !== want ) begin
        $display("FAIL %0s: got %b want %b", what, got, want);
        errors = errors+1;
    end
endtask

task nvwrite(input [6:0] a, input [7:0] d);
    begin
        @(negedge clk); nv_addr=a; nv_din=d; nv_we=1;
        @(negedge clk); nv_we=0;
    end
endtask

// press one pad button (0-based) on player p, everything else released
function [9:0] press(input integer b);
    press = 10'h3ff & ~(10'd1<<(4+b));
endfunction

task settle; repeat(3) @(negedge clk); endtask

reg [8*10:1] got_name;
task read_name(input [2:0] s);
    integer j;
    begin
        for( j=0; j<10; j=j+1 ) begin
            name_slot = s; name_idx = j[3:0];
            #1 got_name[8*(10-j)-:8] = name_char;
        end
    end
endtask

task check_name(input [2:0] s, input [8*10:1] want);
    begin
        read_name(s);
        if( got_name !== want ) begin
            $display("FAIL name slot %0d: '%0s' want '%0s'", s, got_name, want);
            errors = errors+1;
        end
    end
endtask

initial begin
    settle; rst=0; settle;

    // 1. identity after reset, directions and spare bits untouched
    for( k=0; k<6; k=k+1 ) begin
        raw1 = press(k); raw2 = press(k); settle;
        check10(joy1, press(k), "reset identity p1");
        check10(joy2, press(k), "reset identity p2");
    end
    raw1 = 10'b1111110101; settle;
    check10(joy1, 10'b1111110101, "directions pass through");

    // 2. load slot 2 from NVRAM: game button k <- pad button 5-k, name BOB
    for( k=0; k<6; k=k+1 ) nvwrite(7'h20+k, 6-k);
    nvwrite(7'h26,"B"); nvwrite(7'h27,"o"); nvwrite(7'h28,"b");
    sel2 = 2;
    for( k=0; k<6; k=k+1 ) begin
        raw1 = press(k); raw2 = press(k); settle;
        check10(joy1, press(k),   "p1 on slot 0 unaffected");
        check10(joy2, press(5-k), "p2 on slot 2 reversed");
    end

    // 3. readback matches what was loaded, untouched slots read as zero
    for( k=0; k<6; k=k+1 ) begin
        nv_addr = 7'h20+k; #1;
        if( nv_dout !== 6-k ) begin $display("FAIL readback %0d: %0d", k, nv_dout); errors=errors+1; end
        nv_addr = 7'h00+k; #1;
        if( nv_dout !== 0 ) begin $display("FAIL empty readback %0d", k); errors=errors+1; end
    end

    // 4. names
    check_name(2, "Bob       ");
    check_name(0, "Slot 1    ");
    check_name(7, "Slot 8    ");

    // 5. edit page: switching edit slot pushes its stored map to the OSD
    pushes = 0;
    edit_slot = 2; settle;
    if( pushes != 1 ) begin $display("FAIL push count %0d", pushes); errors=errors+1; end
    for( k=0; k<6; k=k+1 ) if( slot_map[k*3+:3] !== 5-k ) begin
        $display("FAIL slot_map[%0d]=%0d", k, slot_map[k*3+:3]); errors=errors+1;
    end

    // 6. store an edited map into slot 4 and use it for player 1
    edit_slot = 4; settle;
    for( k=0; k<6; k=k+1 ) if( slot_map[k*3+:3] !== k ) begin
        $display("FAIL empty slot shows default"); errors=errors+1;
    end
    // LP<-pad 3, MP<-pad 4, HP<-pad 5, LK<-pad 0, MK<-pad 1, HK<-pad 2
    edit_map = {3'd2,3'd1,3'd0,3'd5,3'd4,3'd3};
    uploads = 0;
    store = 1; settle; store = 0; settle;
    if( uploads != 1 ) begin $display("FAIL upload_req count %0d", uploads); errors=errors+1; end
    sel1 = 4;
    for( k=0; k<6; k=k+1 ) begin
        raw1 = press(k); settle;
        check10(joy1, press((k+3)%6), "p1 on stored slot 4");
    end
    store = 1; settle;          // held level must not store twice
    store = 0; settle;
    if( uploads != 2 ) begin $display("FAIL store edge count %0d", uploads); errors=errors+1; end

    // 7. all-zero image (no .nvm yet) means identity everywhere
    for( k=0; k<128; k=k+1 ) nvwrite(k[6:0], 0);
    for( k=0; k<6; k=k+1 ) begin
        raw1 = press(k); raw2 = press(k); settle;
        check10(joy1, press(k), "zeroed p1 identity");
        check10(joy2, press(k), "zeroed p2 identity");
    end

    // 8. two buttons at once on a remapped slot
    for( k=0; k<6; k=k+1 ) nvwrite(7'h40+k, 6-k);
    sel1 = 4; raw1 = press(0) & press(1); settle;
    check10(joy1, press(5) & press(4), "chord remap");

    if( errors ) $display("FAILED with %0d errors", errors);
    else $display("PASS");
    $finish;
end
endmodule
