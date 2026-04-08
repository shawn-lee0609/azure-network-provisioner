"""
Unit tests for validator.py helper functions.
Azure API calls are mocked, no real Azure connection required.
These tests run in CI on every push.
"""

import pytest
from unittest.mock import MagicMock, patch
from validate.validator import (
    build_summary,
    validate_resource_group,
    validate_nsgs,
    validate_route_tables
)

@pytest.fixture
def sample_config():
    """Returns a minimal expected config for testing."""
    return {
        "environment": "dev",
        "resource_group": "rg-network-dev",
        "location": "canadacentral",
        "virtual_network": {
            "name": "vnet-main-dev",
            "address_space": "10.0.0.0/16",
            "subnets": []
        },
        "network_security_groups": [
            {
                "name": "nsg-frontend-dev",
                "rules": [
                    {
                        "name": "Allow-HTTP",
                        "priority": 100,
                        "direction": "Inbound",
                        "access": "Allow",
                        "protocol": "Tcp",
                        "destination_port": "80"
                    }
                ]
            }
        ],
        "route_tables": [
            {
                "name": "rt-custom-dev",
                "routes": [
                    {
                        "name": "route-default-internet",
                        "address_prefix": "0.0.0.0/0",
                        "next_hop_type": "Internet"
                    }
                ]
            }
        ]
    }

# Tests - build_summary
def test_build_summary_all_pass():
    """All PASS results should return correct counts."""
    results = [
        {"status": "PASS"},
        {"status": "PASS"},
        {"status": "PASS"}
    ]
    summary = build_summary(results)
    assert summary["total"] == 3
    assert summary["pass"] == 3
    assert summary["fail"] == 0
    assert summary["drift"] == 0

def test_build_summary_mixed():
    """Mixed results should be counted correctly."""
    results = [
        {"status": "PASS"},
        {"status": "FAIL"},
        {"status": "DRIFT"},
        {"status": "DRIFT"}
    ]
    summary = build_summary(results)
    assert summary["total"] == 4
    assert summary["pass"] == 1
    assert summary["fail"] == 1
    assert summary["drift"] == 2

def test_build_summary_empty():
    """Empty results list should return all zeros."""
    summary = build_summary([])
    assert summary["total"] == 0
    assert summary["pass"] == 0
    assert summary["fail"] == 0
    assert summary["drift"] == 0

# Tests - validate_resource_group
def test_validate_resource_group_pass(sample_config):
    """
    When the resource group exists and location matches,
    all results should be PASS.
    """
    # Create a mock Azure resource client
    mock_client = MagicMock()

    # Simulate Azure returning a resource group with matching location
    mock_rg = MagicMock()
    mock_rg.location = "canadacentral"
    mock_client.resource_groups.get.return_value = mock_rg

    results = validate_resource_group(mock_client, sample_config)

    assert len(results) == 1
    assert results[0].status == "PASS"
    assert results[0].check == "location"

def test_validate_resource_group_drift(sample_config):
    """
    When location does not match expected,
    result should be DRIFT.
    """
    mock_client = MagicMock()

    # Simulate Azure returning wrong location
    mock_rg = MagicMock()
    mock_rg.location = "eastus" # Different from expected "canadacentral"
    mock_client.resource_groups.get.return_value = mock_rg # Act as if by the PI call a mock resource group returns

    results = validate_resource_group(mock_client, sample_config)

    assert len(results) == 1
    assert results[0].status == "DRIFT"
    assert results[0].expected == "canadacentral"
    assert results[0].actual == "eastus"

def test_validate_resource_group_fail(sample_config):
    """
    When the resource group does not exist,
    result should be FAIL.
    """
    mock_client = MagicMock()

    # Simulate Azure throwing an exception (resource not found)
    mock_client.resource_groups.get.side_effect = Exception("ResourceGroupNotFound")

    results = validate_resource_group(mock_client, sample_config)

    assert len(results) == 1
    assert results[0].status == "FAIL"
    assert results[0].check == "existence"

# Tests - validate_nsgs

def test_validate_nsgs_pass(sample_config):
    """
    When NSG exists and all rules match,
    all results should be PASS.
    """

    mock_client = MagicMock()

    # Build a mock NSG with one matching rule
    mock_rule = MagicMock()
    mock_rule.name = "Allow-HTTP"
    mock_rule.priority = 100
    mock_rule.destination_port_range = "80"

    mock_nsg = MagicMock()
    mock_nsg.security_rules = [mock_rule] # Add the rule to the Mock NSG
    mock_client.network_security_groups.get.return_value = mock_nsg

    results = validate_nsgs(mock_client, sample_config)

    # Expect 2 checks: Priority + Destination Port
    assert len(results) == 2
    assert all(r.status == "PASS" for r in results)

def test_validate_nsgs_drift_priority(sample_config):
    """
    When NSG rule priority does not match,
    priority check should be DRIFT.
    """
    mock_client = MagicMock()

    mock_rule = MagicMock()
    mock_rule.name = "Allow-HTTP"
    mock_rule.priority = 200          # expected 100, got 200
    mock_rule.destination_port_range = "80"

    mock_nsg = MagicMock()
    mock_nsg.security_rules = [mock_rule]
    mock_client.network_security_groups.get.return_value = mock_nsg

    results = validate_nsgs(mock_client, sample_config)

    priority_result = next(r for r in results if r.check == "priority")
    assert priority_result.status == "DRIFT"
    assert priority_result.expected == "100"
    assert priority_result.actual == "200"

def test_validate_nsgs_missing_rule(sample_config):
    """
    When an expected NSG rule is missing entirely,
    result should be FAIL.
    """
    mock_client = MagicMock()

    # Return NSG with no rules
    mock_nsg = MagicMock()
    mock_nsg.security_rules = []
    mock_client.network_security_groups.get.return_value = mock_nsg

    results = validate_nsgs(mock_client, sample_config)

    assert len(results) == 1
    assert results[0].status == "FAIL"
    assert results[0].check == "existence"

# Tests - validate_route_tables

def test_validate_route_tables_pass(sample_config):
    """
    When Route Table and routes match expected config,
    all results should be PASS.
    """
    mock_client = MagicMock()

    mock_route = MagicMock()
    mock_route.name = "route-default-internet"
    mock_route.address_prefix = "0.0.0.0/0"
    mock_route.next_hop_type = "Internet"

    mock_rt = MagicMock()
    mock_rt.routes = [mock_route]
    mock_client.route_tables.get.return_value = mock_rt

    results = validate_route_tables(mock_client, sample_config)

    assert len(results) == 2
    assert all(r.status == "PASS" for r in results)


def test_validate_route_tables_drift_next_hop(sample_config):
    """
    When next hop type does not match,
    next_hop_type check should be DRIFT.
    """
    mock_client = MagicMock()

    mock_route = MagicMock()
    mock_route.name = "route-default-internet"
    mock_route.address_prefix = "0.0.0.0/0"
    mock_route.next_hop_type = "VnetLocal"   # expected Internet, got VnetLocal

    mock_rt = MagicMock()
    mock_rt.routes = [mock_route]
    mock_client.route_tables.get.return_value = mock_rt

    results = validate_route_tables(mock_client, sample_config)

    hop_result = next(r for r in results if r.check == "next_hop_type")
    assert hop_result.status == "DRIFT"
    assert hop_result.expected == "Internet"    
    assert hop_result.actual == "VnetLocal"
