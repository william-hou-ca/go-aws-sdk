#!/bin/bash

# VPC Management Script
# Creates/Deletes VPC with 2 public subnets, 2 private subnets, and NAT gateway

set -e

# Configuration
REGION="us-east-1"
VPC_NAME="MyVPC"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
PRIVATE_SUBNET_1_CIDR="10.0.3.0/24"
PRIVATE_SUBNET_2_CIDR="10.0.4.0/24"
AZ1="us-east-1a"
AZ2="us-east-1b"

# Resource tracking file
RESOURCE_FILE="vpc_resources.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
}

# Save resource IDs to file
save_resource() {
    echo "$1=$2" >> $RESOURCE_FILE
}

# Get resource ID from file
get_resource() {
    grep "^$1=" $RESOURCE_FILE 2>/dev/null | cut -d'=' -f2
}

# Create VPC
create_vpc() {
    log_info "Creating VPC..."
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block $VPC_CIDR \
        --region $REGION \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query 'Vpc.VpcId' \
        --output text)
    
    # Enable DNS hostnames and support
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
    
    save_resource "VPC_ID" $VPC_ID
    log_info "VPC created: $VPC_ID"
}

# Create subnets
create_subnets() {
    log_info "Creating subnets..."
    
    # Public Subnet 1
    PUBLIC_SUBNET_1_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PUBLIC_SUBNET_1_CIDR \
        --availability-zone $AZ1 \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-$AZ1}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    save_resource "PUBLIC_SUBNET_1_ID" $PUBLIC_SUBNET_1_ID
    
    # Public Subnet 2
    PUBLIC_SUBNET_2_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PUBLIC_SUBNET_2_CIDR \
        --availability-zone $AZ2 \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-$AZ2}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    save_resource "PUBLIC_SUBNET_2_ID" $PUBLIC_SUBNET_2_ID
    
    # Private Subnet 1
    PRIVATE_SUBNET_1_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PRIVATE_SUBNET_1_CIDR \
        --availability-zone $AZ1 \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-$AZ1}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    save_resource "PRIVATE_SUBNET_1_ID" $PRIVATE_SUBNET_1_ID
    
    # Private Subnet 2
    PRIVATE_SUBNET_2_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PRIVATE_SUBNET_2_CIDR \
        --availability-zone $AZ2 \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-$AZ2}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    save_resource "PRIVATE_SUBNET_2_ID" $PRIVATE_SUBNET_2_ID
    
    # Enable auto-assign public IP for public subnets
    aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1_ID --map-public-ip-on-launch
    aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_2_ID --map-public-ip-on-launch
    
    log_info "Subnets created successfully"
}

# Create Internet Gateway
create_internet_gateway() {
    log_info "Creating Internet Gateway..."
    
    IGW_ID=$(aws ec2 create-internet-gateway \
        --region $REGION \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$VPC_NAME-IGW}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    save_resource "IGW_ID" $IGW_ID
    
    # Attach IGW to VPC
    aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
    
    log_info "Internet Gateway created and attached: $IGW_ID"
}

# Create route tables
create_route_tables() {
    log_info "Creating route tables..."
    
    # Create public route table
    PUBLIC_RT_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --region $REGION \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Public-RT}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    save_resource "PUBLIC_RT_ID" $PUBLIC_RT_ID
    
    # Create private route table
    PRIVATE_RT_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --region $REGION \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Private-RT}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    save_resource "PRIVATE_RT_ID" $PRIVATE_RT_ID
    
    # Add internet route to public route table
    aws ec2 create-route \
        --route-table-id $PUBLIC_RT_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID \
        --region $REGION
    
    # Associate public subnets with public route table
    aws ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_1_ID
    aws ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_2_ID
    
    # Associate private subnets with private route table
    aws ec2 associate-route-table --route-table-id $PRIVATE_RT_ID --subnet-id $PRIVATE_SUBNET_1_ID
    aws ec2 associate-route-table --route-table-id $PRIVATE_RT_ID --subnet-id $PRIVATE_SUBNET_2_ID
    
    log_info "Route tables created and configured"
}

# Create NAT Gateway
create_nat_gateway() {
    log_info "Creating NAT Gateway..."
    
    # Allocate Elastic IP
    EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
        --domain vpc \
        --region $REGION \
        --query 'AllocationId' \
        --output text)
    save_resource "EIP_ALLOCATION_ID" $EIP_ALLOCATION_ID
    
    log_info "Elastic IP allocated: $EIP_ALLOCATION_ID"
    
    # Create NAT Gateway in first public subnet
    NAT_GW_ID=$(aws ec2 create-nat-gateway \
        --subnet-id $PUBLIC_SUBNET_1_ID \
        --allocation-id $EIP_ALLOCATION_ID \
        --region $REGION \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$VPC_NAME-NAT}]" \
        --query 'NatGateway.NatGatewayId' \
        --output text)
    save_resource "NAT_GW_ID" $NAT_GW_ID
    
    log_info "Waiting for NAT Gateway to become available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID --region $REGION
    
    # Add NAT gateway route to private route table
    aws ec2 create-route \
        --route-table-id $PRIVATE_RT_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id $NAT_GW_ID \
        --region $REGION
    
    log_info "NAT Gateway created: $NAT_GW_ID"
}

# Create all resources
create_all_resources() {
    log_info "Starting VPC creation..."
    
    # Initialize resource file
    > $RESOURCE_FILE
    
    create_vpc
    create_subnets
    create_internet_gateway
    create_route_tables
    create_nat_gateway
    
    log_info "VPC setup completed successfully!"
    display_created_resources
}

# Display created resources
display_created_resources() {
    log_info "Created Resources:"
    echo "=================="
    cat $RESOURCE_FILE
    echo "=================="
}

# Delete NAT Gateway
delete_nat_gateway() {
    local nat_gw_id=$(get_resource "NAT_GW_ID")
    local eip_alloc_id=$(get_resource "EIP_ALLOCATION_ID")
    
    if [ -n "$nat_gw_id" ]; then
        log_info "Deleting NAT Gateway: $nat_gw_id"
        aws ec2 delete-nat-gateway --nat-gateway-id $nat_gw_id --region $REGION
        
        # Wait for NAT Gateway to be deleted
        log_info "Waiting for NAT Gateway to be deleted..."
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids $nat_gw_id --region $REGION
    fi
    
    if [ -n "$eip_alloc_id" ]; then
        log_info "Releasing Elastic IP: $eip_alloc_id"
        aws ec2 release-address --allocation-id $eip_alloc_id --region $REGION
    fi
}

# Delete Internet Gateway
delete_internet_gateway() {
    local igw_id=$(get_resource "IGW_ID")
    local vpc_id=$(get_resource "VPC_ID")
    
    if [ -n "$igw_id" ] && [ -n "$vpc_id" ]; then
        log_info "Detaching and deleting Internet Gateway: $igw_id"
        aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --region $REGION
        aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --region $REGION
    fi
}

# Delete route tables
delete_route_tables() {
    local public_rt_id=$(get_resource "PUBLIC_RT_ID")
    local private_rt_id=$(get_resource "PRIVATE_RT_ID")
    
    if [ -n "$public_rt_id" ]; then
        log_info "Deleting public route table: $public_rt_id"
        aws ec2 delete-route-table --route-table-id $public_rt_id --region $REGION
    fi
    
    if [ -n "$private_rt_id" ]; then
        log_info "Deleting private route table: $private_rt_id"
        aws ec2 delete-route-table --route-table-id $private_rt_id --region $REGION
    fi
}

# Delete subnets
delete_subnets() {
    local subnets=(
        $(get_resource "PUBLIC_SUBNET_1_ID")
        $(get_resource "PUBLIC_SUBNET_2_ID")
        $(get_resource "PRIVATE_SUBNET_1_ID")
        $(get_resource "PRIVATE_SUBNET_2_ID")
    )
    
    for subnet_id in "${subnets[@]}"; do
        if [ -n "$subnet_id" ]; then
            log_info "Deleting subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id $subnet_id --region $REGION
        fi
    done
}

# Delete VPC
delete_vpc() {
    local vpc_id=$(get_resource "VPC_ID")
    
    if [ -n "$vpc_id" ]; then
        log_info "Deleting VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id $vpc_id --region $REGION
    fi
}

# Delete all resources
delete_all_resources() {
    if [ ! -f "$RESOURCE_FILE" ]; then
        log_error "Resource file not found. Nothing to delete."
        return 1
    fi
    
    log_warn "This will delete all VPC resources. Continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Deletion cancelled."
        return
    fi
    
    log_info "Starting VPC deletion..."
    
    # Delete in reverse order of creation
    delete_nat_gateway
    delete_internet_gateway
    delete_route_tables
    delete_subnets
    delete_vpc
    
    # Remove resource file
    rm -f $RESOURCE_FILE
    
    log_info "VPC deletion completed successfully!"
}

# Show status
show_status() {
    if [ ! -f "$RESOURCE_FILE" ]; then
        log_info "No VPC resources found (resource file doesn't exist)."
        return
    fi
    
    log_info "Current VPC Resources:"
    echo "=================="
    if [ -f "$RESOURCE_FILE" ]; then
        cat $RESOURCE_FILE
    else
        echo "No resources found"
    fi
    echo "=================="
}

# Main menu
show_menu() {
    echo ""
    echo "=========================================="
    echo "         VPC Management Script"
    echo "=========================================="
    echo "1. Create VPC with all resources"
    echo "2. Delete VPC and all resources"
    echo "3. Show current resources status"
    echo "4. Exit"
    echo "=========================================="
    echo -n "Please choose an option [1-4]: "
}

# Main function
main() {
    check_aws_cli
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                create_all_resources
                ;;
            2)
                delete_all_resources
                ;;
            3)
                show_status
                ;;
            4)
                log_info "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option. Please choose 1, 2, 3, or 4."
                ;;
        esac
        
        echo ""
        echo "Press any key to continue..."
        read -n 1 -s
    done
}

# Run main function
main "$@"