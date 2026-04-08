"""
validator.py

Connects to Azure using environment-based credentials,
retrieves the deployed network resources, and compare them
against the expected configuration defined in expected_config.json.

Outputs a structured validation result for each resource,
flagging any configuration drift detected.
"""

import json
import os
import sys
from dataclasses import dataclass
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.resource import ResourceManagementClient

# Data Classes

@dataclass
class ValidationResult:
    """
    Represents the result of a single validation check.

    resource   : name of the resource being validated
    check      : what specific property was checked
    status     : "PASS", "FAIL", or "DRIFT"
    expected   : what the config says it should be
    actual     : what Azure actually has
    message    : human-readable explanation
    """
    resource: str
    check: str
    status: str
    expected: str
    actual: str
    message: Optional[str] = None

# Azure Authentication

def get_credentials():
    """
    Authenticates using DefaultAzureCredential.
    Automatically picks up the existing PowerShell Az session,
    environment variables, or managed identity — whichever is available.
    """
    return DefaultAzureCredential()

# Config Loader

def load_expected_config(config_path: str) -> dict:
    """
    Loads the expected configuration from a JSON file.
    Exits with an error if the file is not found or is malformed.
    """
    if not os.path.exists(config_path):
        print(f"[ERROR] Config file not found: {config_path}")
        sys.exit(1)

    with open(config_path, "r") as f:
        return json.load(f)

# Validation Functions

# Validate whether the expected resource group exists or drifted
def validate_resource_group(resource_client: ResourceManagementClient,
                            config: dict) -> list[ValidationResult]:

    """
    Checks that the Resource Group exists and is in the correct location.
    """
    results = []
    rg_name = config["resource_group"] # Extracts the value from expected_config.json by using the key "resource_group" from .json
    expected_location = config["location"]

    try:
        rg = resource_client.resource_groups.get(rg_name)
        actual_location = rg.location

        # Check whether the location matches
        if actual_location == expected_location:
            results.append(ValidationResult(
                resource=rg_name,
                check="location",
                status="PASS",
                expected=expected_location,
                actual=actual_location
            ))
        else:
            results.append(ValidationResult(
                resource=rg.name,
                check="location",
                status="DRIFT",
                expected=expected_location,
                actual=actual_location,
                message=f"Location mismatch: expected '{expected_location}', got '{actual_location}'"
            ))

    except Exception:
        # Resource Group does not exist at all
        results.append(ValidationResult(
            resource=rg_name,
            check="existence",
            status="FAIL",
            expected="exists",
            actual="not found",
            message=f"Resource Group '{rg_name}' does not exist"
        ))

    return results


def validate_virtual_network(network_client: NetworkManagementClient,
                             config: dict) -> list[ValidationResult]:
    """
    Checks that the VNet exists, has the correct address space,
    and that all expected subnets are present with correct prefixes,
    NSG associations, and Route Table associations.
    """
    results = []
    rg_name = config["resource_group"]
    vnet_config = config["virtual_network"]
    vnet_name = vnet_config["name"]

    try:
        vnet = network_client.virtual_networks.get(rg_name, vnet_name)

        # Check VNet address space
        actual_address_space = vnet.address_space.address_prefixes[0]
        expected_address_space = vnet_config["address_space"]

        if actual_address_space == expected_address_space:
            results.append(ValidationResult(
                resource=vnet_name,
                check="address_space",
                status="PASS",
                expected=expected_address_space,
                actual=actual_address_space
            ))
        else:
            results.append(ValidationResult(
                resource=vnet_name,
                check="address_space",
                status="DRIFT",
                expected=expected_address_space,
                actual=actual_address_space,
                message="VNet address space mismatch"
            ))

        # Build a lookup map of actual subnets for easy comparison
        # { "snet-frontend": <Subnet object>, "snet-backend": <Subnet object> }
        actual_subnets = {subnet.name: subnet for subnet in vnet.subnets}

        # Validate each expected subnet
        for expected_subnet in vnet_config["subnets"]:
            subnet_name = expected_subnet["name"]

            if subnet_name not in actual_subnets:
                # Subnet is completely missing
                results.append(ValidationResult(
                    resource=subnet_name,
                    check="existence",
                    status="FAIL",
                    expected="exists",
                    actual="not found",
                    message=f"Subnet '{subnet_name}' does not exist in VNet '{vnet_name}'"
                ))
                continue

            actual_subnet = actual_subnets[subnet_name]

            # Check subnet address prefix
            if actual_subnet.address_prefix == expected_subnet["address_prefix"]:
                results.append(ValidationResult(
                    resource=subnet_name,
                    check="address_prefix",
                    status="PASS",
                    expected=expected_subnet["address_prefix"],
                    actual=actual_subnet.address_prefix
                ))
            else:
                results.append(ValidationResult(
                    resource=subnet_name,
                    check="address_prefix",
                    status="DRIFT",
                    expected=expected_subnet["address_prefix"],
                    actual=actual_subnet.address_prefix,
                    message=f"Subnet address prefix mismatch for '{subnet_name}'"
                ))

            # Check NSG association
            if "nsg" in expected_subnet:
                expected_nsg = expected_subnet["nsg"]
                # NSG id is a full ARM resource ID — extract just the name at the end
                # e.g. /subscriptions/.../networkSecurityGroups/nsg-frontend-dev → nsg-frontend-dev
                actual_nsg = actual_subnet.network_security_group.id.split("/")[-1] \
                    if actual_subnet.network_security_group else "none"

                if actual_nsg == expected_nsg:
                    results.append(ValidationResult(
                        resource=subnet_name,
                        check="nsg_association",
                        status="PASS",
                        expected=expected_nsg,
                        actual=actual_nsg
                    ))
                else:
                    results.append(ValidationResult(
                        resource=subnet_name,
                        check="nsg_association",
                        status="DRIFT",
                        expected=expected_nsg,
                        actual=actual_nsg,
                        message=f"NSG association mismatch for subnet '{subnet_name}'"
                    ))

            # Check Route Table association
            if "route_table" in expected_subnet:
                expected_rt = expected_subnet["route_table"]
                actual_rt = actual_subnet.route_table.id.split("/")[-1] \
                    if actual_subnet.route_table else "none"

                if actual_rt == expected_rt:
                    results.append(ValidationResult(
                        resource=subnet_name,
                        check="route_table_association",
                        status="PASS",
                        expected=expected_rt,
                        actual=actual_rt
                    ))
                else:
                    results.append(ValidationResult(
                        resource=subnet_name,
                        check="route_table_association",
                        status="DRIFT",
                        expected=expected_rt,
                        actual=actual_rt,
                        message=f"Route Table association mismatch for subnet '{subnet_name}'"
                    ))

    except Exception as e:
        results.append(ValidationResult(
            resource=vnet_name,
            check="existence",
            status="FAIL",
            expected="exists",
            actual="not found",
            message=str(e)
        ))

    return results

def validate_nsgs(network_client: NetworkManagementClient,
                  config: dict) -> list[ValidationResult]:
    """
    Checks that each expected NSG exists and contains
    all expected security rules with correct properties.
    """
    results = []
    rg_name = config["resource_group"]

    for expected_nsg in config["network_security_groups"]:
        nsg_name = expected_nsg["name"]

        try:
            actual_nsg = network_client.network_security_groups.get(rg_name, nsg_name)

            # Build a lookup map of actual rules by name
            actual_rules = {rule.name: rule for rule in actual_nsg.security_rules}

            for expected_rule in expected_nsg["rules"]:
                rule_name = expected_rule["name"]

                if rule_name not in actual_rules:
                    results.append(ValidationResult(
                        resource=f"{nsg_name}/{rule_name}",
                        check="existence",
                        status="FAIL",
                        expected="exists",
                        actual="not found",
                        message=f"Rule '{rule_name}' missing from NSG '{nsg_name}'"
                    ))
                    continue

                actual_rule = actual_rules[rule_name]

                # Check priority
                if actual_rule.priority == expected_rule["priority"]:
                    results.append(ValidationResult(
                        resource=f"{nsg_name}/{rule_name}",
                        check="priority",
                        status="PASS",
                        expected=str(expected_rule["priority"]),
                        actual=str(actual_rule.priority)
                    ))
                else:
                    results.append(ValidationResult(
                        resource=f"{nsg_name}/{rule_name}",
                        check="priority",
                        status="DRIFT",
                        expected=str(expected_rule["priority"]),
                        actual=str(actual_rule.priority),
                        message=f"Priority mismatch for rule '{rule_name}' in '{nsg_name}'"
                    ))

                # Check destination port
                if actual_rule.destination_port_range == expected_rule["destination_port"]:
                    results.append(ValidationResult(
                        resource=f"{nsg_name}/{rule_name}",
                        check="destination_port",
                        status="PASS",
                        expected=expected_rule["destination_port"],
                        actual=actual_rule.destination_port_range
                    ))
                else:
                    results.append(ValidationResult(
                        resource=f"{nsg_name}/{rule_name}",
                        check="destination_port",
                        status="DRIFT",
                        expected=expected_rule["destination_port"],
                        actual=actual_rule.destination_port_range,
                        message=f"Destination port mismatch for rule '{rule_name}'"
                    ))

        except Exception as e:
            results.append(ValidationResult(
                resource=nsg_name,
                check="existence",
                status="FAIL",
                expected="exists",
                actual="not found",
                message=str(e)
            ))

    return results


def validate_route_tables(network_client: NetworkManagementClient,
                           config: dict) -> list[ValidationResult]:
    """
    Checks that each expected Route Table exists and contains
    all expected routes with correct address prefixes and next hop types.
    """
    results = []
    rg_name = config["resource_group"]

    for expected_rt in config["route_tables"]:
        rt_name = expected_rt["name"]

        try:
            actual_rt = network_client.route_tables.get(rg_name, rt_name)
            actual_routes = {route.name: route for route in actual_rt.routes}

            for expected_route in expected_rt["routes"]:
                route_name = expected_route["name"]

                if route_name not in actual_routes:
                    results.append(ValidationResult(
                        resource=f"{rt_name}/{route_name}",
                        check="existence",
                        status="FAIL",
                        expected="exists",
                        actual="not found",
                        message=f"Route '{route_name}' missing from Route Table '{rt_name}'"
                    ))
                    continue

                actual_route = actual_routes[route_name]

                # Check address prefix
                if actual_route.address_prefix == expected_route["address_prefix"]:
                    results.append(ValidationResult(
                        resource=f"{rt_name}/{route_name}",
                        check="address_prefix",
                        status="PASS",
                        expected=expected_route["address_prefix"],
                        actual=actual_route.address_prefix
                    ))
                else:
                    results.append(ValidationResult(
                        resource=f"{rt_name}/{route_name}",
                        check="address_prefix",
                        status="DRIFT",
                        expected=expected_route["address_prefix"],
                        actual=actual_route.address_prefix,
                        message=f"Address prefix mismatch for route '{route_name}'"
                    ))

                # Check next hop type
                if actual_route.next_hop_type == expected_route["next_hop_type"]:
                    results.append(ValidationResult(
                        resource=f"{rt_name}/{route_name}",
                        check="next_hop_type",
                        status="PASS",
                        expected=expected_route["next_hop_type"],
                        actual=actual_route.next_hop_type
                    ))
                else:
                    results.append(ValidationResult(
                        resource=f"{rt_name}/{route_name}",
                        check="next_hop_type",
                        status="DRIFT",
                        expected=expected_route["next_hop_type"],
                        actual=actual_route.next_hop_type,
                        message=f"Next hop type mismatch for route '{route_name}'"
                    ))

        except Exception as e:
            results.append(ValidationResult(
                resource=rt_name,
                check="existence",
                status="FAIL",
                expected="exists",
                actual="not found",
                message=str(e)
            ))

    return results

def build_summary(results: list[dict]) -> dict:
    """
    Calculates total, pass, fail, and drift counts
    from the full results list.
    """
    return {
        "total": len(results),
        "pass":  sum(1 for r in results if r["status"] == "PASS"),
        "fail":  sum(1 for r in results if r["status"] == "FAIL"),
        "drift": sum(1 for r in results if r["status"] == "DRIFT")
    }

# Main Entry Point

def main():
    # Load expected config
    config_path = os.path.join(os.path.dirname(__file__), "expected_config.json")
    config = load_expected_config(config_path)

    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
    if not subscription_id:
        print("[ERROR] AZURE_SUBSCRIPTION_ID environment variable is not set.")
        sys.exit(1)

    # Authenticate and create Azure SDK clients
    credential = get_credentials()
    network_client = NetworkManagementClient(credential, subscription_id)
    resource_client = ResourceManagementClient(credential, subscription_id)

    print(f"\n{'='*50}")
    print(f"  Azure Network Validator - {config['environment']}")
    print(f"{'='*50}\n")

    # Run all validation checks and collect results
    all_results = []
    all_results += validate_resource_group(resource_client, config)
    all_results += validate_virtual_network(network_client, config)
    all_results += validate_nsgs(network_client, config)
    all_results += validate_route_tables(network_client, config)

    # Print results to console
    for result in all_results:
        color = {"PASS": "\033[92m", "FAIL": "\033[91m", "DRIFT": "\033[93m"}
        reset = "\033[0m"
        status_colored = f"{color[result.status]}[{result.status}]{reset}"
        print(f"{status_colored} {result.resource} — {result.check}")
        if result.message:
            print(f"       → {result.message}")

    # Summary
    total  = len(all_results)
    passed = sum(1 for r in all_results if r.status == "PASS")
    failed = sum(1 for r in all_results if r.status == "FAIL")
    drift  = sum(1 for r in all_results if r.status == "DRIFT")

    print(f"\n{'='*50}")
    print(f"  Validation Summary")
    print(f"{'='*50}")
    print(f"  Total checks : {total}")
    print(f"  PASS         : {passed}")
    print(f"  FAIL         : {failed}")
    print(f"  DRIFT        : {drift}")
    print(f"{'='*50}\n")

    # Save results as JSON for report_generator.py to consume
    output_path = os.path.join(os.path.dirname(__file__), "validation_results.json")
    with open(output_path, "w") as f:
        json.dump(
            [vars(r) for r in all_results],
            f,
            indent=2
        )
    print(f"[INFO] Results saved to: {output_path}")

    # Exit with non-zero code if any checks failed or drifted
    # This allows CI/CD pipeline to detect validation failures
    if failed > 0 or drift > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()

