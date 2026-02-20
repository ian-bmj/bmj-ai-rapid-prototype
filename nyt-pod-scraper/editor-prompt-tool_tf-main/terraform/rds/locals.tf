locals {
  cyclestate_tag = contains(["dev", "stg"], var.stack) ? { CycleState = tostring(var.cyclestate) } : {}
}