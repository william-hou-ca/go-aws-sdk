package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/ec2/imds"
)

func main() {
	ctx := context.TODO()
	
	// 1. Load default configuration and create IMDS client
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Unable to load AWS configuration: %v", err)
	}

	client := imds.NewFromConfig(cfg)

	// 2. Get basic instance information
	fmt.Println("=== EC2 Instance Metadata ===")
	
	// Get instance ID
	instanceID, err := getInstanceID(client, ctx)
	if err != nil {
		log.Printf("Warning: Unable to get instance ID: %v", err)
	} else {
		fmt.Printf("Instance ID: %s\n", instanceID)
	}

	// Get instance region
	region, err := getRegion(client, ctx)
	if err != nil {
		log.Printf("Warning: Unable to get region: %v", err)
	} else {
		fmt.Printf("Region: %s\n", region)
	}

	// Get private IP address
	privateIP, err := getPrivateIP(client, ctx)
	if err != nil {
		log.Printf("Warning: Unable to get private IP: %v", err)
	} else {
		fmt.Printf("Private IP: %s\n", privateIP)
	}

	// Get instance type
	instanceType, err := getInstanceType(client, ctx)
	if err != nil {
		log.Printf("Warning: Unable to get instance type: %v", err)
	} else {
		fmt.Printf("Instance Type: %s\n", instanceType)
	}

	// 3. Get complete instance identity document
	fmt.Println("\n=== Instance Identity Document ===")
	identityDoc, err := getInstanceIdentityDocument(client, ctx)
	if err != nil {
		log.Printf("Warning: Unable to get instance identity document: %v", err)
	} else {
		fmt.Printf("Account ID: %s\n", identityDoc.AccountID)
		fmt.Printf("Architecture: %s\n", identityDoc.Architecture)
		fmt.Printf("Availability Zone: %s\n", identityDoc.AvailabilityZone)
		fmt.Printf("Image ID: %s\n", identityDoc.ImageID)
		fmt.Printf("Kernel ID: %s\n", identityDoc.KernelID)
		fmt.Printf("Pending Time: %s\n", identityDoc.PendingTime.Format(time.RFC3339))
	}

	// 4. Check IAM information
	fmt.Println("\n=== IAM Information ===")
	iamInfo, err := getIAMInfo(client, ctx)
	if err != nil {
		log.Printf("Warning: Unable to get IAM information: %v", err)
	} else {
		fmt.Printf("IAM Role ARN: %s\n", iamInfo.InstanceProfileArn)
		fmt.Printf("Last Updated: %s\n", iamInfo.LastUpdated.Format(time.RFC3339))
	}
}

// Get instance ID
func getInstanceID(client *imds.Client, ctx context.Context) (string, error) {
	result, err := client.GetMetadata(ctx, &imds.GetMetadataInput{
		Path: "instance-id",
	})
	if err != nil {
		return "", err
	}
	defer result.Content.Close()
	
	content, err := io.ReadAll(result.Content)
	if err != nil {
		return "", err
	}
	
	return string(content), nil
}

// Get region
func getRegion(client *imds.Client, ctx context.Context) (string, error) {
	result, err := client.GetRegion(ctx, &imds.GetRegionInput{})
	if err != nil {
		return "", err
	}
	return result.Region, nil
}

// Get private IP address
func getPrivateIP(client *imds.Client, ctx context.Context) (string, error) {
	result, err := client.GetMetadata(ctx, &imds.GetMetadataInput{
		Path: "local-ipv4",
	})
	if err != nil {
		return "", err
	}
	defer result.Content.Close()
	
	content, err := io.ReadAll(result.Content)
	if err != nil {
		return "", err
	}
	
	return string(content), nil
}

// Get instance type
func getInstanceType(client *imds.Client, ctx context.Context) (string, error) {
	result, err := client.GetMetadata(ctx, &imds.GetMetadataInput{
		Path: "instance-type",
	})
	if err != nil {
		return "", err
	}
	defer result.Content.Close()
	
	content, err := io.ReadAll(result.Content)
	if err != nil {
		return "", err
	}
	
	return string(content), nil
}

// Get instance identity document
func getInstanceIdentityDocument(client *imds.Client, ctx context.Context) (*imds.InstanceIdentityDocument, error) {
	result, err := client.GetInstanceIdentityDocument(ctx, &imds.GetInstanceIdentityDocumentInput{})
	if err != nil {
		return nil, err
	}
	return &result.InstanceIdentityDocument, nil
}

// Get IAM information
func getIAMInfo(client *imds.Client, ctx context.Context) (*imds.IAMInfo, error) {
	result, err := client.GetIAMInfo(ctx, &imds.GetIAMInfoInput{})
	if err != nil {
		return nil, err
	}
	return &result.IAMInfo, nil
}
