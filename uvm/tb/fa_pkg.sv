
`timescale 1ns/1ps
package fa_pkg;
  import uvm_pkg::*;	
  `include "uvm_macros.svh"	

  `include "components/fa_settings.svh"
  `include "components/fa_items.svh"	
  `include "components/master/m_items.svh"
  `include "components/slave/s_items.svh"
  `include "components/fa_config.svh"
  `include "components/fa_stimulus.svh"
  `include "components/fa_reference_model.svh"
  `include "components/master/m_sequence.svh"
  `include "components/slave/s_sequence.svh"
  `include "components/master/m_sequencer.svh"
  `include "components/slave/s_sequencer.svh"
  `include "components/master/m_driver.svh"
  `include "components/slave/s_driver.svh"
  `include "components/fa_protocol_checker.svh"
  `include "components/master/m_monitor.svh"
  `include "components/slave/s_monitor.svh"
  `include "components/fa_reset_observer.svh"
  `include "components/fa_scoreboard.svh"
  `include "components/fa_coverage.svh"
  `include "components/master/m_agent.svh"
  `include "components/slave/s_agent.svh"
  `include "components/fa_env.svh"
  `include "tb/fa_test.svh"
endpackage
