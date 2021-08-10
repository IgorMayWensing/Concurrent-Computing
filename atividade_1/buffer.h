#ifndef __BUFFER_H_
#define __BUFFER_H_

typedef struct buffer_s {
    /// Array onde devem ser colocados os elementos. No init_buffer(),
    /// esse ponteiro é incializado para uma região que consegue
    /// armazenar capacity elementos. No destroy_buffer(), essa região
    /// deve ser liberada
    int* data;
    /// indice onde irá ocorrer a próxima inserção (put)
    int put_idx;
    /// indice onde irá ocorrer a próxima remoção (take)
    int take_idx;
    /// Quantos elementos cabem em data
    int capacity;
    /// Quantos elementos estão em data
    int size;
} buffer_t;

void init_buffer(buffer_t* b, int capacity) {
    b.data = (int*) malloc(capacity * sizeof(int));
    b.put_idx = 0;
    b.take_idx = 0;
    b.capacity = capacity;
    b.size = 0;
}

void destroy_buffer(buffer_t* b){
    free(b.data);
}

int take_buffer(buffer_t* b){
  if(b.size == 0){
     return -1;
  }
  if(b.take_idx == b.capacity){
    b.take_idx = 0;
  }
  b.size--;
  b.take_idx++;
  return b.data[b.take_idx-1];
}

int put_buffer(buffer_t* b, int val){
  if(b.size == b.capacity){
     return -1;
  }

  if(b.put_idx == b.capacity){
      b.put_idx = 0;
  }
  b.data[b.put_idx] = val;
  b.>size++;
  b.put_idx++;
  return 0;
}

void dump_buffer(buffer_t* b);


#endif /*__BUFFER_H_*/
