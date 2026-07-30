package enrollment

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/example/self-hosted-pki/broker/internal/issuer"
)

var ErrReplay = errors.New("GitLab token was already used")

// ReplayStore atomically reserves a GitLab jti. The returned release function
// must be called with false only when the downstream CA never issued a
// certificate, allowing a transient CA failure to be retried safely.
type ReplayStore interface {
	Claim(context.Context, string, time.Time) (func(context.Context, bool), error)
}

type memoryReplayStore struct {
	mu    sync.Mutex
	items map[string]time.Time
}

func NewMemoryReplayStore() ReplayStore {
	return &memoryReplayStore{items: map[string]time.Time{}}
}

func (s *memoryReplayStore) Claim(_ context.Context, jti string, expiresAt time.Time) (func(context.Context, bool), error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for id, expiry := range s.items {
		if now.After(expiry) {
			delete(s.items, id)
		}
	}
	if _, exists := s.items[jti]; exists {
		return nil, ErrReplay
	}
	s.items[jti] = expiresAt
	return func(_ context.Context, successful bool) {
		if successful {
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		delete(s.items, jti)
	}, nil
}

type dynamoDBAPI interface {
	PutItem(context.Context, *dynamodb.PutItemInput, ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	DeleteItem(context.Context, *dynamodb.DeleteItemInput, ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
}

type dynamoDBReplayStore struct {
	client dynamoDBAPI
	table  string
}

func NewDynamoDBReplayStore(ctx context.Context, table string) (ReplayStore, error) {
	if table == "" {
		return nil, fmt.Errorf("replay_table_name is required for DynamoDB replay protection")
	}
	config, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	return &dynamoDBReplayStore{client: dynamodb.NewFromConfig(config), table: table}, nil
}

func (s *dynamoDBReplayStore) Claim(ctx context.Context, jti string, expiresAt time.Time) (func(context.Context, bool), error) {
	requestID := issuer.NewTokenID()
	_, err := s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		ConditionExpression: aws.String("attribute_not_exists(jti)"),
		Item: map[string]types.AttributeValue{
			"jti":        &types.AttributeValueMemberS{Value: jti},
			"expires_at": &types.AttributeValueMemberN{Value: fmt.Sprintf("%d", expiresAt.Unix())},
			"request_id": &types.AttributeValueMemberS{Value: requestID},
		},
	})
	if err != nil {
		var conditional *types.ConditionalCheckFailedException
		if errors.As(err, &conditional) {
			return nil, ErrReplay
		}
		return nil, fmt.Errorf("claim GitLab token jti: %w", err)
	}
	return func(ctx context.Context, successful bool) {
		if successful {
			return
		}
		_, _ = s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName:           aws.String(s.table),
			ConditionExpression: aws.String("request_id = :request_id"),
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":request_id": &types.AttributeValueMemberS{Value: requestID},
			},
			Key: map[string]types.AttributeValue{
				"jti": &types.AttributeValueMemberS{Value: jti},
			},
		})
	}, nil
}
