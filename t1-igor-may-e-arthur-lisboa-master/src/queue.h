#include <stdio.h> 
#include <stdlib.h>
#include "types.h"

order_t pedidoVazio;

struct QNode { 
	order_t pedido; 
	struct QNode* next; 
}; 

struct Queue { 
	struct QNode *front, *rear; 
}; 

struct QNode* newNode(order_t pedido) 
{ 
	struct QNode* temp = (struct QNode*)malloc(sizeof(struct QNode)); 
	temp->pedido = pedido; 
	temp->next = NULL; 
	return temp; 
} 

struct Queue* createQueue() 
{ 
	struct Queue* q = (struct Queue*)malloc(sizeof(struct Queue)); 
	q->front = q->rear = NULL; 
	return q; 
} 

void enQueue(struct Queue* q, order_t pedido) 
{ 
	struct QNode* temp = newNode(pedido); 

	if (q->rear == NULL) { 
		q->front = q->rear = temp; 
		return; 
	} 

	q->rear->next = temp; 
	q->rear = temp; 
} 

order_t deQueue(struct Queue* q) 
{ 
	if (q->front == NULL) 
		return pedidoVazio; 

	struct QNode* temp = q->front; 

	q->front = q->front->next; 

	if (q->front == NULL) 
		q->rear = NULL; 

	order_t pedido = temp->pedido;

	free(temp); 

	return pedido;
} 