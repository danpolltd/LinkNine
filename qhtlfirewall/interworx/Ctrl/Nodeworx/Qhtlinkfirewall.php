<?php
/*
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################
*/

class Ctrl_Nodeworx_Qhtlfirewall extends Ctrl_Nodeworx_Plugin
{
    protected function _init()
    {
        chmod('/usr/local/interworx/plugins/qhtlfirewall', 0711);
        chmod('/usr/local/interworx/plugins/qhtlfirewall/lib', 0711);
        chmod('/usr/local/interworx/plugins/qhtlfirewall/lib/index.pl', 0711);
        chmod('/usr/local/interworx/plugins/qhtlfirewall/lib/reseller.pl', 0711);
    }

    public function launchAction()
    {
        $this->getView()->assign('title', 'QhtLink Firewall Services');
        $this->getView()->assign('template', 'admin');
    }

    public function indexAction()
    {
        if (IW::NW()->isReseller()) {
            $this->_getPlugin()->runReseller();
        } else {
            $this->_getPlugin()->runAdmin();
        }
        exit;
    }
}
