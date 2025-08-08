set sdc_version 1.3

set tmrgSucces 0
set tmrgFailed 0
proc constrainNet netName {
  global tmrgSucces
  global tmrgFailed
  # find nets matching netName pattern
  set nets [dc::get_net $netName]
  if {[llength $nets] != 0} {
    set_dont_touch $nets
    incr tmrgSucces
  } else {
    puts "\[TMRG\] Warning! Net(s) '$netName' not found"
    incr tmrgFailed
  }
}

constrainNet /clk_i
constrainNet /clk_iA
constrainNet /clk_iB
constrainNet /clk_iC
constrainNet /counter_qA[*]
constrainNet /counter_qB[*]
constrainNet /counter_qC[*]
constrainNet /counter_qVotedA[*]
constrainNet /counter_qVotedB[*]
constrainNet /counter_qVotedC[*]
constrainNet /overflow_qA
constrainNet /overflow_qB
constrainNet /overflow_qC
constrainNet /overflow_qVotedA
constrainNet /overflow_qVotedB
constrainNet /overflow_qVotedC
constrainNet /rst_ni
constrainNet /rst_niA
constrainNet /rst_niB
constrainNet /rst_niC


    puts "TMRG successful  $tmrgSucces failed $tmrgFailed"
